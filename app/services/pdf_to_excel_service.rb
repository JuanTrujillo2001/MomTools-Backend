require 'pdf/reader'
require 'axlsx'
require 'json'

class PdfToExcelService
  PAGES_PER_CHUNK = 2
  MAX_RETRIES_PER_CHUNK = 3
  RETRY_BASE_DELAY_SECONDS = 2

  def initialize(file_path, output_path: nil)
    @file_path = file_path
    @output_path = output_path
  end

  def call
    data = extract_data
    file = generate_excel(data)

    file
  end

  private

  def extract_data
    reader = PDF::Reader.new(@file_path)
    pages = reader.pages
    items = []

    pages_per_chunk = if pages.size >= 100
      6
    elsif pages.size >= 50
      4
    else
      PAGES_PER_CHUNK
    end

    total_chunks = (pages.size.to_f / pages_per_chunk).ceil

    pages.each_slice(pages_per_chunk).with_index do |page_group, idx|
      chunk_text = page_group.map(&:text).join("\n")

      attempt = 0
      begin
        json = call_gpt(chunk_text, chunk_index: idx + 1, total_chunks: total_chunks)
        parsed = parse_json(json)
        items.concat(Array(parsed))
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Net::ReadTimeout, Net::OpenTimeout => e
        attempt += 1
        raise if attempt > MAX_RETRIES_PER_CHUNK

        sleep_seconds = RETRY_BASE_DELAY_SECONDS**attempt
        Rails.logger.warn("[PdfToExcelService] retry chunk=#{idx + 1}/#{total_chunks} attempt=#{attempt} error=#{e.class} msg=#{e.message} sleep=#{sleep_seconds}s")
        sleep(sleep_seconds)
        retry
      end
    end

    items
  end

  def call_gpt(texto, chunk_index: nil, total_chunks: nil)
    client = OpenAI::Client.new

    chunk_prefix = ""
    if chunk_index && total_chunks
      chunk_prefix = "Parte #{chunk_index} de #{total_chunks}.\n"
    end

    prompt = <<~TEXT
        #{chunk_prefix}
        Extrae productos de este catálogo.

        Reglas IMPORTANTES:

        1. Cada producto puede tener UNO o VARIOS códigos.
        - Todos los códigos deben ir en un array llamado "codigos".
        - Ejemplo: ["I-26A", "8943768510"]

        2. Los códigos:
        - Son números o combinaciones (letras, guiones)
        - Aparecen normalmente al inicio de la línea

        3. El producto:
        - Es la descripción del artículo
        - Debe ser texto limpio (sin códigos ni marca)

        4. La marca:
        - Es una palabra corta (ej: NPW, BTK, TECNIPARTES, GUTEN)
        - Normalmente aparece antes del precio

        5. El precio:
        - Es el último número del producto
        - Puede venir con puntos (ej: 96.639)
        - Debe devolverse SIN puntos ni símbolos
        - Ej: 96639

        6. Ignora:
        - Títulos
        - Textos como "PRECIOS MAS IVA"
        - Líneas que no sean productos

        Formato de salida (JSON válido):

        [
        {
            "codigos": [],
            "producto": "",
            "marca": "",
            "precio": ""
        }
        ]

        Responde SOLO con JSON válido. No expliques nada.

        Texto:
        #{texto}
        TEXT

    response = client.responses.create(
      parameters: {
        model: "gpt-4.1-mini",
        input: prompt
      }
    )

    response.dig("output", 0, "content", 0, "text")
  end

  def parse_json(json)
    s = json.to_s.strip
    s = s.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "")

    begin
      return JSON.parse(s)
    rescue JSON::ParserError
    end

    if (start_idx = s.index('[')) && (end_idx = s.rindex(']')) && end_idx > start_idx
      candidate = s[start_idx..end_idx]
      return JSON.parse(candidate)
    end

    []
  rescue
    []
  end

  def generate_excel(data)
    file_path = @output_path.presence || "tmp/#{File.basename(@file_path, File.extname(@file_path))}.xlsx"

    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Productos") do |sheet|
        sheet.add_row ["codigo", "producto", "marca", "precio"]

        Array(data).each do |item|
          next unless item.is_a?(Hash)

          codigos = item["codigos"]
          codigos = [item["codigo"]] if codigos.blank?
          codigos = Array(codigos).map { |c| c.to_s.strip }.reject(&:blank?)

          producto = item["producto"].to_s
          marca = item["marca"].to_s
          precio = item["precio"].to_s

          if codigos.empty?
            sheet.add_row [nil, producto, marca, precio]
          else
            codigos.each do |codigo|
              sheet.add_row [codigo, producto, marca, precio]
            end
          end
        end
      end

      p.serialize(file_path)
    end

    file_path
  end
end