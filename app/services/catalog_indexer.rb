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

    # Delete existing items for this sheet_config before re-indexing
    @sheet_config.catalog_items.delete_all

    # Track unique items per indexing run to avoid creating duplicates when
    # the Excel contains identical rows (same code, description, price, brand).
    seen_items = Set.new

    # Prefer the generated Excel file (stored in S3) if present
    if @catalog.excel_file.attached?
      source_path = FileCache.fetch(@catalog.excel_file.blob).to_s
    else
      cached_path = FileCache.fetch(@catalog.file.blob)
      file_ext = File.extname(cached_path.to_s).downcase

      source_path = if file_ext == ".pdf"
        original_filename = @catalog.file.filename.to_s
        excel_filename = "#{File.basename(original_filename, File.extname(original_filename))}.xlsx"
        output_path = Rails.root.join("tmp", excel_filename).to_s
        generated_xlsx_path = PdfToExcelService.new(cached_path.to_s, output_path: output_path).call

        pdf_key = @catalog.file.blob.key.to_s
        excel_key = pdf_key.sub(/\.pdf\z/i, ".xlsx")
        excel_key = "#{pdf_key}.xlsx" if excel_key == pdf_key

        File.open(generated_xlsx_path, "rb") do |f|
          @catalog.excel_file.attach(
            io: f,
            filename: excel_filename,
            content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            key: excel_key
          )
        end

        FileCache.fetch(@catalog.excel_file.blob).to_s
      else
        cached_path.to_s
      end
    end

    original_ext = File.extname(@catalog.file.filename.to_s).downcase.strip
    
    # Always pass extension explicitly to Roo
    ext_sym = original_ext.gsub('.', '').to_sym if original_ext.present?
    
    workbook = if ext_sym.present?
      Roo::Spreadsheet.open(source_path.to_s, extension: ext_sym)
    else
      Roo::Spreadsheet.open(source_path.to_s)
    end

    # Find actual sheet name (handle whitespace normalization)
    sheet_name_normalized = normalize_sheet_name(@sheet_config.sheet_name)
    actual_sheet_name = workbook.sheets.find do |name|
      normalize_sheet_name(name) == sheet_name_normalized
    end

    return { success: false, error: "Sheet '#{@sheet_config.sheet_name}' not found in workbook" } unless actual_sheet_name

    sheet = workbook.sheet(actual_sheet_name)
    last_row = sheet.last_row

    return { success: true } if last_row.nil?

    consecutive_empty_rows = 0
    max_empty_rows = 50  # Stop after 50 consecutive empty rows

    (1..last_row).each do |row_number|
      # Extract values from configured columns
      codes = extract_cells(sheet, row_number, code_cols)
      descriptions = extract_cells(sheet, row_number, desc_cols)
      prices = extract_cells(sheet, row_number, price_cols, kind: :price)
      brands = extract_cells(sheet, row_number, brand_cols)

      # Check if row is completely empty (no code, no desc, no price, no brand)
      row_empty = codes.all?(&:blank?) && descriptions.all?(&:blank?) && prices.all?(&:blank?) && brands.all?(&:blank?)

      if row_empty
        consecutive_empty_rows += 1
        break if consecutive_empty_rows >= max_empty_rows
        next
      else
        consecutive_empty_rows = 0
      end

      # Skip row if no valid code found
      next if codes.empty? || codes.all?(&:blank?)

      # Skip header-like rows (heuristic: code looks like a header word)
      next if looks_like_header?(codes.first)

      # If code_cols and price_cols have same length, pair them by index.
      # If there is a single price value in the row, reuse it for all codes.
      # Otherwise (multiple prices, different number of columns), fall back to
      # the first price found.
      paired = code_cols.size == price_cols.size && code_cols.size > 0

      single_row_price = nil
      if prices.size == 1
        single_row_price = parse_price(prices.first)
      end

      codes.each_with_index do |code_value, idx|
        next if code_value.blank?

        description = descriptions.join(" | ").presence
        brand = brands.join(" | ").presence

        price = if paired && prices[idx].present?
          # One price column per code column – use the price that shares index.
          parse_price(prices[idx])
        elsif single_row_price
          # Exactly one price value in the row – reuse it for all codes.
          single_row_price
        elsif prices.any?
          # Multiple prices but different number of columns – best effort: first price.
          parse_price(prices.first)
        else
          nil
        end

        # Skip if no price (price is required, description is optional)
        next if price.nil?

        # Deduplicate exact duplicates within this sheet_config: if another row
        # already produced the same combination of code, description, price and
        # brand in this indexing run, skip creating it again.
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
        # Convert 12345.0 to "12345" for codes
        raw_value.to_i.to_s
      else
        raw_value.to_s.strip
      end

      values << text_value unless text_value.blank?
    end
    values
  end

  def parse_price(value)
    s = value.to_s.strip
    return nil if s.blank?

    # Remove currency symbols and spaces
    s = s.gsub(/[^0-9,\.\-]/, '')
    return nil if s.blank?

    # Handle different decimal/thousand separators
    if s.include?('.') && s.include?(',')
      if s.rindex(',') > s.rindex('.')
        s = s.delete('.').tr(',', '.')
      else
        s = s.delete(',')
      end
    elsif s.include?(',')
      # Could be decimal separator or thousand separator
      if s.match?(/\A\d{1,3}(?:,\d{3})+(?:\.\d+)?\z/)
        s = s.delete(',')
      else
        s = s.tr(',', '.')
      end
    end

    BigDecimal(s)
  rescue ArgumentError, TypeError
    nil
  end

  def looks_like_header?(value)
    return true if value.blank?

    normalized = value.to_s.strip.downcase
    header_words = %w[codigo código code ref referencia reference item producto product sku]

    header_words.any? { |word| normalized == word || normalized.start_with?("#{word}.") }
  end
end
