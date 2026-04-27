require "pdf/reader"

class PdfToExcelProviderSelector
  PROVIDER_OPENAI = "openai"
  PROVIDER_ADOBE = "adobe"

  def initialize(pdf_path)
    @pdf_path = pdf_path
  end

  def call
    text = extract_first_page_text
    snippet = text.to_s.gsub(/\s+/, " ").strip[0, 500]
    Rails.logger.info("[PdfToExcelProviderSelector] first_page_chars=#{text.to_s.length} snippet=\"#{snippet}\"")

    if text.to_s.strip.empty?
      Rails.logger.info("[PdfToExcelProviderSelector] decision=#{PROVIDER_ADOBE} reason=empty_first_page_text")
      return PROVIDER_ADOBE
    end

    heuristic = structured_table_heuristic(text)
    Rails.logger.info("[PdfToExcelProviderSelector] heuristic is_structured_table=#{heuristic[:is_structured_table]} score=#{heuristic[:score]} details=\"#{heuristic[:details]}\"")
    if heuristic[:is_structured_table]
      Rails.logger.info("[PdfToExcelProviderSelector] decision=#{PROVIDER_ADOBE} reason=heuristic_structured_table score=#{heuristic[:score]} details=\"#{heuristic[:details]}\"")
      return PROVIDER_ADOBE
    end

    decision = ask_openai(text)
    normalized = normalize_decision(decision)
    Rails.logger.info("[PdfToExcelProviderSelector] model=#{ENV.fetch("PDF_TO_EXCEL_SELECTOR_MODEL", "gpt-4.1-mini")} raw=\"#{decision.to_s.strip}\" normalized=#{normalized}")
    normalized
  rescue StandardError => e
    Rails.logger.warn("[PdfToExcelProviderSelector] fallback=openai error=#{e.class} msg=#{e.message}")
    PROVIDER_OPENAI
  end

  private

  def extract_first_page_text
    reader = PDF::Reader.new(@pdf_path)
    page = reader.pages.first
    page ? page.text.to_s : ""
  end

  def ask_openai(first_page_text)
    client = OpenAI::Client.new

    prompt = <<~TEXT
      Decide el mejor método para convertir un PDF a Excel.

      Responde SOLO con una palabra: "adobe" o "openai".

      Criterios:
      - Responde "adobe" si el PDF parece una tabla estructurada donde basta convertir a XLSX.
      - Responde "openai" si el PDF parece un catálogo en texto libre donde hay que interpretar columnas (código, producto, marca, precio) o la estructura no es una tabla limpia.

      Texto (primera página):
      #{first_page_text}
      TEXT

    response = client.responses.create(
      parameters: {
        model: ENV.fetch("PDF_TO_EXCEL_SELECTOR_MODEL", "gpt-4.1-mini"),
        input: prompt
      }
    )

    response.dig("output", 0, "content", 0, "text") || response["output_text"]
  end

  def structured_table_heuristic(text)
    raw_lines = text.to_s.lines.first(120).map { |l| l.to_s.strip }.reject(&:empty?)
    return { is_structured_table: false, score: 0, details: "no_lines" } if raw_lines.empty?

    delimiter_like = 0
    multi_space_like = 0
    numeric_like = 0
    column_counts = []

    raw_lines.each do |raw_line|
      normalized = raw_line.gsub(/\s+/, " ")

      delimiter_like += 1 if raw_line.include?("|") || raw_line.include?("\t") || raw_line.include?(";")
      multi_space_like += 1 if raw_line.match?(/\S\s{2,}\S/)
      numeric_like += 1 if normalized.match?(/\b\d{1,3}([\.,]\d{3})*([\.,]\d{2})?\b/)

      if raw_line.include?("|")
        column_counts << raw_line.split("|").map(&:strip).reject(&:empty?).size
      elsif raw_line.include?("\t")
        column_counts << raw_line.split("\t").map(&:strip).reject(&:empty?).size
      else
        column_counts << raw_line.split(/\s{2,}/).map(&:strip).reject(&:empty?).size
      end
    end

    lines = raw_lines.size
    avg_cols = (column_counts.sum.to_f / [column_counts.size, 1].max)
    consistent_cols = column_counts.count { |c| c >= 3 } >= (lines * 0.5)

    score = 0
    score += 2 if (delimiter_like.to_f / lines) >= 0.2
    score += 2 if (multi_space_like.to_f / lines) >= 0.35
    score += 1 if (numeric_like.to_f / lines) >= 0.25
    score += 2 if consistent_cols
    score += 1 if avg_cols >= 4

    details = "lines=#{lines} delim=#{delimiter_like} multispace=#{multi_space_like} numeric=#{numeric_like} avg_cols=#{format('%.2f', avg_cols)} consistent_cols=#{consistent_cols}"
    { is_structured_table: score >= 5, score: score, details: details }
  end

  def normalize_decision(text)
    s = text.to_s.strip.downcase
    return PROVIDER_ADOBE if s.include?(PROVIDER_ADOBE)
    return PROVIDER_OPENAI if s.include?(PROVIDER_OPENAI)

    PROVIDER_OPENAI
  end
end
