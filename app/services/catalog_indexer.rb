require 'set'

class CatalogIndexer
  def initialize(sheet_config)
    @sheet_config = sheet_config
    @catalog = sheet_config.catalog
  end

  def call
    return { success: false, error: "No file attached" } unless @catalog.file.attached?

    code_cols = Array(@sheet_config.code_columns)
    desc_cols = Array(@sheet_config.description_columns)
    price_cols = Array(@sheet_config.price_columns)
    brand_cols = Array(@sheet_config.brand_columns)

    return { success: false, error: "No code columns configured" } if code_cols.empty?

    @sheet_config.catalog_items.delete_all

    seen_items = Set.new

    source_path, ext_sym = resolve_source_path
    return { success: false, error: "Catalog is still processing" } if ext_sym.nil?

    Rails.logger.info("[CatalogIndexer] opening source_path=#{source_path} ext_sym=#{ext_sym}")

    workbook = ext_sym.present? \
      ? Roo::Spreadsheet.open(source_path, extension: ext_sym) \
      : Roo::Spreadsheet.open(source_path)

    sheet_name_normalized = normalize_sheet_name(@sheet_config.sheet_name)
    actual_sheet_name = workbook.sheets.find do |name|
      normalize_sheet_name(name) == sheet_name_normalized
    end

    return { success: false, error: "Sheet '#{@sheet_config.sheet_name}' not found in workbook" } unless actual_sheet_name

    sheet = workbook.sheet(actual_sheet_name)
    last_row = sheet.last_row

    return { success: true } if last_row.nil?

    consecutive_empty_rows = 0
    max_empty_rows = 50

    (1..last_row).each do |row_number|
      codes = extract_cells(sheet, row_number, code_cols)
      descriptions = extract_cells(sheet, row_number, desc_cols)
      prices = extract_cells(sheet, row_number, price_cols, kind: :price)
      brands = extract_cells(sheet, row_number, brand_cols)

      row_empty = codes.all?(&:blank?) && descriptions.all?(&:blank?) && prices.all?(&:blank?) && brands.all?(&:blank?)

      if row_empty
        consecutive_empty_rows += 1
        break if consecutive_empty_rows >= max_empty_rows
        next
      else
        consecutive_empty_rows = 0
      end

      next if codes.empty? || codes.all?(&:blank?)
      next if looks_like_header?(codes.first)

      paired = code_cols.size == price_cols.size && code_cols.size > 0

      single_row_price = nil
      if prices.size == 1
        single_row_price = parse_price(prices.first)
      end

      parsed_prices = prices.map { |p| parse_price(p) }.compact

      codes.each_with_index do |code_value, idx|
        next if code_value.blank?

        description = descriptions.join(" | ").presence
        brand = brands.join(" | ").presence

        if codes.size == 1 && !paired && parsed_prices.size > 1
          parsed_prices.each do |price|
            dedup_key = [code_value, description, price.to_s, brand]
            next if seen_items.include?(dedup_key)
            seen_items << dedup_key

            @sheet_config.catalog_items.create!(
              sheet_name: @sheet_config.sheet_name,
              row_number: row_number,
              code: code_value,
              description: description,
              price: price,
              brand: brand
            )
          end
          next
        end

        if codes.size > 1 && !paired && parsed_prices.size > 1
          parsed_prices.each do |price|
            dedup_key = [code_value, description, price.to_s, brand]
            next if seen_items.include?(dedup_key)
            seen_items << dedup_key

            @sheet_config.catalog_items.create!(
              sheet_name: @sheet_config.sheet_name,
              row_number: row_number,
              code: code_value,
              description: description,
              price: price,
              brand: brand
            )
          end
          next
        end

        price = if paired && prices[idx].present?
          parse_price(prices[idx])
        elsif single_row_price
          single_row_price
        elsif parsed_prices.any?
          parsed_prices.first
        else
          nil
        end

        next if price.nil?

        dedup_key = [code_value, description, price.to_s, brand]
        next if seen_items.include?(dedup_key)
        seen_items << dedup_key

        @sheet_config.catalog_items.create!(
          sheet_name: @sheet_config.sheet_name,
          row_number: row_number,
          code: code_value,
          description: description,
          price: price,
          brand: brand
        )
      end
    end

    { success: true }
  rescue StandardError => e
    Rails.logger.error("[CatalogIndexer] Error indexing sheet_config_id=#{@sheet_config.id}: #{e.class} - #{e.message}")
    { success: false, error: e.message }
  end

  private

  def resolve_source_path
    if @catalog.excel_file.attached?
      # Archivo xlsx generado desde PDF — siempre es xlsx
      path = FileCache.fetch(@catalog.excel_file.blob).to_s
      return [path, :xlsx]
    end

    # Archivo original subido por el usuario
    cached_path = FileCache.fetch(@catalog.file.blob).to_s

    # Leer extensión desde el filename original del blob, nunca del path cacheado
    # porque FileCache genera nombres con sufijos random que confunden a Roo
    ext = File.extname(@catalog.file.blob.filename.to_s).downcase.strip
    ext_sym = ext.present? ? ext.delete_prefix(".").to_sym : nil

    # Si la extensión es pdf, el excel todavía no fue generado
    return [cached_path, nil] if ext_sym == :pdf || ext_sym.nil?

    [cached_path, ext_sym]
  end

  def normalize_sheet_name(value)
    value.to_s.strip.gsub(/\s+/, ' ')
  end

  def column_letter_to_index(letter)
    s = letter.to_s.strip.upcase
    return nil if s.blank?
    return nil unless s.match?(/\A[A-Z]+\z/)

    s.chars.reduce(0) { |acc, ch| acc * 26 + (ch.ord - "A".ord + 1) }
  end

  def extract_cells(sheet, row_number, column_letters, kind: :text)
    values = []
    Array(column_letters).each do |col_letter|
      col_index = column_letter_to_index(col_letter)
      next if col_index.nil?

      raw_value = sheet.cell(row_number, col_index)

      text_value = if kind == :price && raw_value.is_a?(Numeric)
        format('%.2f', raw_value.to_f)
      elsif raw_value.is_a?(Float) && raw_value == raw_value.to_i
        raw_value.to_i.to_s
      else
        raw_value.to_s.strip
      end

      text_value = strip_html(text_value)

      values << text_value unless text_value.blank?
    end
    values
  end

  def parse_price(value)
    s = value.to_s.strip
    return nil if s.blank?

    s = s.gsub(/[^0-9,\.\-]/, '')
    return nil if s.blank?

    if s.include?('.') && s.include?(',')
      if s.rindex(',') > s.rindex('.')
        s = s.delete('.').tr(',', '.')
      else
        s = s.delete(',')
      end
    elsif s.include?(',')
      if s.match?(/\A\d{1,3}(?:,\d{3})+(?:\.\d+)?\z/)
        s = s.delete(',')
      else
        s = s.tr(',', '.')
      end
    end

    price = BigDecimal(s)
    return nil if price <= 0
    price
  rescue ArgumentError, TypeError
    nil
  end

  def looks_like_header?(value)
    return true if value.blank?

    normalized = value.to_s.strip.downcase
    header_words = %w[codigo código code ref referencia reference item producto product sku]

    header_words.any? { |word| normalized == word || normalized.start_with?("#{word}.") }
  end

  def strip_html(value)
    return value unless value.to_s.match?(/<[^>]+>/)
    ActionView::Base.full_sanitizer.sanitize(value.to_s).strip
  end
end