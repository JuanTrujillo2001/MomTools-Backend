class SheetConfigAutoConfigurator
  MAX_ROWS = ENV.fetch("SHEET_AUTOCONFIG_MAX_ROWS", "25").to_i
  MAX_COLS = ENV.fetch("SHEET_AUTOCONFIG_MAX_COLS", "80").to_i

  def initialize(sheet_config)
    @sheet_config = sheet_config
    @catalog = sheet_config.catalog
  end

  def call
    return { success: false, error: "No catalog file attached" } unless @catalog.file.attached?

    source_path, ext_sym = resolve_source_path
    workbook = ext_sym.present? ? Roo::Spreadsheet.open(source_path.to_s, extension: ext_sym) : Roo::Spreadsheet.open(source_path.to_s)

    actual_sheet_name = find_actual_sheet_name(workbook, @sheet_config.sheet_name)
    return { success: false, error: "Sheet '#{@sheet_config.sheet_name}' not found" } unless actual_sheet_name

    sheet = workbook.sheet(actual_sheet_name)
    sample = build_sheet_sample(sheet, actual_sheet_name)

    ai = ask_openai(sample)
    parsed = parse_json(ai)

    attrs = normalize_attrs(parsed)

    if attrs[:code_columns].empty?
      return { success: false, error: "AI could not identify any code columns" }
    end

    if attrs[:price_columns].empty?
      return { success: false, error: "AI could not identify any price columns" }
    end

    @sheet_config.update!(attrs)

    index_result = CatalogIndexer.new(@sheet_config).call
    return { success: false, error: (index_result[:error].presence || "Indexing failed") } unless index_result[:success]

    { success: true, attrs: attrs, index_result: index_result }
  rescue StandardError => e
    Rails.logger.warn("[SheetConfigAutoConfigurator] sheet_config_id=#{@sheet_config.id} error=#{e.class} msg=#{e.message}")
    { success: false, error: e.message }
  end

  private

  def resolve_source_path
    if @catalog.excel_file.attached?
      path = FileCache.fetch(@catalog.excel_file.blob).to_s
      return [path, :xlsx]
    end

    cached_path = FileCache.fetch(@catalog.file.blob).to_s
    # Tomar la extensión del filename original del blob, no del path cacheado
    ext = File.extname(@catalog.file.blob.filename.to_s).downcase.strip
    ext_sym = ext.present? ? ext.delete_prefix(".").to_sym : nil
    [cached_path, ext_sym]
  end

  def find_actual_sheet_name(workbook, sheet_name)
    normalized_target = normalize_sheet_name(sheet_name)
    workbook.sheets.find { |n| normalize_sheet_name(n) == normalized_target }
  end

  def normalize_sheet_name(value)
    value.to_s.strip.gsub(/\s+/, " ")
  end

  # Converts a 1-based column index to Excel letter notation (1→A, 26→Z, 27→AA, etc.)
  def col_index_to_letter(index)
    result = ""
    while index > 0
      index, remainder = (index - 1).divmod(26)
      result = (65 + remainder).chr + result
    end
    result
  end

  def build_sheet_sample(sheet, sheet_name)
    last_row = sheet.last_row.to_i
    last_row = 1 if last_row <= 0
    max_row = [MAX_ROWS, last_row].min

    last_col = sheet.last_column.to_i
    last_col = 1 if last_col <= 0
    last_col = [last_col, MAX_COLS].min

    # Detect first fully-empty column and cut there
    empty_col_index = nil
    (1..last_col).each do |col_idx|
      all_blank = (1..max_row).all? do |row_idx|
        v = sheet.cell(row_idx, col_idx)
        v.nil? || v.to_s.strip.empty?
      end

      if all_blank
        empty_col_index = col_idx
        break
      end
    end

    effective_last_col = empty_col_index ? [empty_col_index - 1, 1].max : last_col
    col_letters = (1..effective_last_col).map { |i| col_index_to_letter(i) }

    data = (1..max_row).map do |row_idx|
      (1..effective_last_col).map do |col_idx|
        raw = sheet.cell(row_idx, col_idx)
        raw.nil? ? "" : raw.to_s.strip
      end
    end

    {
      sheet_name: sheet_name.to_s,
      rows: max_row,
      cols: effective_last_col,
      column_letters: col_letters,
      data: data,
    }
  end

  def ask_openai(sample)
    model = ENV.fetch("SHEET_AUTOCONFIG_MODEL", "gpt-4.1-mini")
    client = OpenAI::Client.new

    col_letters = sample[:column_letters] || []

    # Build a human-readable preview: header row + first 5 data rows
    header_line = col_letters.join(" | ")
    separator_line = col_letters.map { |_| "---" }.join(" | ")
    data_lines = sample[:data].first(5).map { |row| row.join(" | ") }.join("\n")
    table_preview = [header_line, separator_line, data_lines].join("\n")

    prompt = <<~TEXT
      Analiza esta hoja de Excel e identifica TODAS las columnas que corresponden a cada categoría.

      REGLAS IMPORTANTES:
      - Puede haber MÁS DE UNA columna de código y MÁS DE UNA columna de precio. Debes incluirlas TODAS.
      - Ejemplos de múltiples códigos: "Código interno", "Código proveedor", "SKU", "Referencia", "EAN/Barcode"
      - Ejemplos de múltiples precios: "Precio lista", "Precio contado", "Precio mayorista", "Precio USD", "Precio 1", "Precio 2"
      - code_columns y price_columns son OBLIGATORIOS y NO pueden estar vacíos
      - description_columns y brand_columns son opcionales; devuelve [] si no estás seguro

      REGLA DE EXCLUSIVIDAD — MUY IMPORTANTE:
      - Cada columna solo puede aparecer en UNA categoría. No se puede repetir la misma letra en múltiples categorías.
      - Orden de prioridad si una columna encaja en más de una categoría:
          1. code_columns  (máxima prioridad)
          2. price_columns
          3. description_columns
          4. brand_columns  (mínima prioridad)
      - Ejemplo INCORRECTO: code_columns: ["A"], price_columns: ["A"] — la columna A no puede estar en ambas.
      - Ejemplo INCORRECTO: description_columns: ["C"], brand_columns: ["C"] — la columna C no puede estar en ambas.
      - Ejemplo CORRECTO: si la columna A tiene precios pero el header dice "Suzuki", clasificarla como price_columns: ["A"] y NO incluirla en brand_columns.
      - Antes de responder, verifica que ninguna letra aparezca más de una vez en todo el JSON.

      Categorías a identificar:
      - code_columns: columnas con códigos, referencias, SKU, EAN/barcode de productos (1 o más)
      - price_columns: columnas con precios en cualquier moneda o modalidad (1 o más)
      - description_columns: columnas con nombre, descripción o detalle del producto (opcional)
      - brand_columns: columnas con marca, fabricante o proveedor (opcional)

      Responde SOLO con JSON válido, sin explicaciones ni markdown:

      {
        "code_columns": ["A", "B"],
        "price_columns": ["D", "E", "F"],
        "description_columns": ["C"],
        "brand_columns": []
      }

      Columnas disponibles: #{col_letters.join(", ")}

      Vista previa de la hoja (primeras filas):
      #{table_preview}

      Muestra completa en JSON:
      #{JSON.generate(sample)}
    TEXT

    response = client.responses.create(
      parameters: {
        model: model,
        input: prompt,
      }
    )

    response.dig("output", 0, "content", 0, "text") || response["output_text"]
  end

  def parse_json(json)
    s = json.to_s.strip
    # Strip markdown code fences if present
    s = s.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "")

    begin
      return JSON.parse(s)
    rescue JSON::ParserError
    end

    # Fallback: extract first {...} block
    if (start_idx = s.index("{")) && (end_idx = s.rindex("}")) && end_idx > start_idx
      candidate = s[start_idx..end_idx]
      begin
        return JSON.parse(candidate)
      rescue JSON::ParserError
      end
    end

    {}
  rescue StandardError
    {}
  end

  def normalize_attrs(parsed)
    h = parsed.is_a?(Hash) ? parsed : {}

    {
      code_columns: normalize_column_letters(h["code_columns"]),
      price_columns: normalize_column_letters(h["price_columns"]),
      description_columns: normalize_column_letters(h["description_columns"]),
      brand_columns: normalize_column_letters(h["brand_columns"]),
    }
  end

  def normalize_column_letters(value)
    Array(value)
      .map { |v| v.to_s.strip.upcase }
      .select { |v| v.match?(/\A[A-Z]+\z/) }
      .uniq
  end
end