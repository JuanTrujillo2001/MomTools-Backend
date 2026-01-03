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

    return { success: false, error: "No code columns configured" } if code_cols.empty?

    # Delete existing items for this sheet_config before re-indexing
    @sheet_config.catalog_items.delete_all

    items_created = 0

    # Use cached file to avoid re-downloading from S3 on every config update
    cached_path = FileCache.fetch(@catalog.file.blob)
    workbook = Roo::Spreadsheet.open(cached_path.to_s)

    # Find actual sheet name (handle whitespace normalization)
    sheet_name_normalized = normalize_sheet_name(@sheet_config.sheet_name)
    actual_sheet_name = workbook.sheets.find do |name|
      normalize_sheet_name(name) == sheet_name_normalized
    end

    return { success: false, error: "Sheet '#{@sheet_config.sheet_name}' not found in workbook" } unless actual_sheet_name

    sheet = workbook.sheet(actual_sheet_name)
    last_row = sheet.last_row

    return { success: true, items_created: 0 } if last_row.nil?

    consecutive_empty_rows = 0
    max_empty_rows = 50  # Stop after 50 consecutive empty rows

    (1..last_row).each do |row_number|
      # Extract values from configured columns
      codes = extract_cells(sheet, row_number, code_cols)
      descriptions = extract_cells(sheet, row_number, desc_cols)
      prices = extract_cells(sheet, row_number, price_cols, kind: :price)

      # Check if row is completely empty (no code, no desc, no price)
      row_empty = codes.all?(&:blank?) && descriptions.all?(&:blank?) && prices.all?(&:blank?)

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

      # If code_cols and price_cols have same length, pair them by index
      # Otherwise, use all prices for each code
      paired = code_cols.size == price_cols.size && code_cols.size > 0

      codes.each_with_index do |code_value, idx|
        next if code_value.blank?

        description = descriptions.join(" | ").presence
        price = if paired && prices[idx].present?
          parse_price(prices[idx])
        elsif prices.any?
          parse_price(prices.first)
        else
          nil
        end

        # Skip if no price (price is required, description is optional)
        next if price.nil?

        @sheet_config.catalog_items.create!(
          sheet_name: @sheet_config.sheet_name,
          row_number: row_number,
          code: code_value,
          description: description,
          price: price
        )
        items_created += 1
      end
    end

    { success: true, items_created: items_created }
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
