require "json"
require "uri"
require "fileutils"
require "faraday"

class AdobePdfToExcelService
  DEFAULT_POLL_INTERVAL_SECONDS = 2
  DEFAULT_MAX_POLL_SECONDS = 180
  DEFAULT_REQUEST_TIMEOUT = 180
  DEFAULT_OPEN_TIMEOUT = 60

  DEFAULT_MAX_RETRIES = 3
  DEFAULT_RETRY_BASE_DELAY_SECONDS = 2

  def initialize(file_path, output_path: nil)
    @file_path = file_path
    @output_path = output_path
  end

  def call
    Rails.logger.info("[AdobePdfToExcelService] start")
    token = fetch_access_token
    asset = create_asset(token, media_type: "application/pdf")
    upload_asset(asset.fetch("uploadUri"), media_type: "application/pdf")

    location = submit_export_job(token, asset.fetch("assetID"), target_format: "xlsx")
    status_payload = poll_job(token, location)

    download_uri = extract_download_uri(status_payload)
    raise "Adobe job finished but no downloadUri returned" if download_uri.to_s.strip.empty?

    bytes = download_result(download_uri)
    write_output(bytes)
  end

  private

  def client_id
    ENV.fetch("PDF_SERVICES_CLIENT_ID")
  end

  def client_secret
    ENV.fetch("PDF_SERVICES_CLIENT_SECRET")
  end

  def poll_interval_seconds
    ENV.fetch("ADOBE_PDF_SERVICES_POLL_INTERVAL_SECONDS", DEFAULT_POLL_INTERVAL_SECONDS.to_s).to_i
  end

  def max_poll_seconds
    ENV.fetch("ADOBE_PDF_SERVICES_MAX_POLL_SECONDS", DEFAULT_MAX_POLL_SECONDS.to_s).to_i
  end

  def max_retries
    ENV.fetch("ADOBE_PDF_SERVICES_MAX_RETRIES", DEFAULT_MAX_RETRIES.to_s).to_i
  end

  def retry_base_delay_seconds
    ENV.fetch("ADOBE_PDF_SERVICES_RETRY_BASE_DELAY_SECONDS", DEFAULT_RETRY_BASE_DELAY_SECONDS.to_s).to_i
  end

  def with_retries(stage)
    attempt = 0

    begin
      attempt += 1
      yield
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Net::ReadTimeout, Net::OpenTimeout => e
      raise if attempt > max_retries

      sleep_seconds = retry_base_delay_seconds**attempt
      Rails.logger.warn("[AdobePdfToExcelService] retry stage=#{stage} attempt=#{attempt}/#{max_retries} error=#{e.class} msg=#{e.message} sleep=#{sleep_seconds}s")
      sleep(sleep_seconds)
      retry
    end
  end

  def build_faraday(base_url)
    request_timeout = ENV.fetch("ADOBE_PDF_SERVICES_REQUEST_TIMEOUT", DEFAULT_REQUEST_TIMEOUT.to_s).to_i
    open_timeout = ENV.fetch("ADOBE_PDF_SERVICES_OPEN_TIMEOUT", DEFAULT_OPEN_TIMEOUT.to_s).to_i

    Faraday.new(url: base_url) do |f|
      f.options.timeout = request_timeout
      f.options.open_timeout = open_timeout
    end
  end

  def fetch_access_token
    Rails.logger.info("[AdobePdfToExcelService] token_request")
    conn = build_faraday("https://pdf-services.adobe.io")
    res = with_retries("token") do
      conn.post("/token") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          client_id: client_id,
          client_secret: client_secret
        )
      end
    end

    raise "Adobe token request failed status=#{res.status} body=#{res.body}" unless res.status.to_i == 200

    data = JSON.parse(res.body.to_s)
    token = data["access_token"]
    raise "Adobe token response missing access_token" if token.to_s.strip.empty?

    token
  end

  def create_asset(token, media_type:)
    Rails.logger.info("[AdobePdfToExcelService] create_asset")
    conn = build_faraday("https://pdf-services.adobe.io")
    res = with_retries("create_asset") do
      conn.post("/assets") do |req|
        req.headers["X-API-Key"] = client_id
        req.headers["Authorization"] = "Bearer #{token}"
        req.headers["Content-Type"] = "application/json"
        req.body = { mediaType: media_type }.to_json
      end
    end

    raise "Adobe create asset failed status=#{res.status} body=#{res.body}" unless res.status.to_i == 200

    JSON.parse(res.body.to_s)
  end

  def upload_asset(upload_uri, media_type:)
    Rails.logger.info("[AdobePdfToExcelService] upload_asset")
    bytes = File.binread(@file_path)
    conn = build_faraday("https://example.invalid")
    res = with_retries("upload_asset") do
      conn.put(upload_uri) do |req|
        req.headers["Content-Type"] = media_type
        req.body = bytes
      end
    end

    unless [200, 201].include?(res.status.to_i)
      raise "Adobe upload asset failed status=#{res.status}"
    end

    true
  end

  def submit_export_job(token, asset_id, target_format:)
    Rails.logger.info("[AdobePdfToExcelService] submit_export_job")
    conn = build_faraday("https://pdf-services.adobe.io")
    res = with_retries("submit_export_job") do
      conn.post("/operation/exportpdf") do |req|
        req.headers["x-api-key"] = client_id
        req.headers["Authorization"] = "Bearer #{token}"
        req.headers["Content-Type"] = "application/json"
        req.body = {
          assetID: asset_id,
          targetFormat: target_format
        }.to_json
      end
    end

    raise "Adobe exportpdf submit failed status=#{res.status} body=#{res.body}" unless res.status.to_i == 201

    location = res.headers["location"] || res.headers["Location"]
    raise "Adobe exportpdf response missing location header" if location.to_s.strip.empty?

    location
  end

  def poll_job(token, location)
    started = Time.current
    status_url = if location.to_s.end_with?("/status")
      location
    else
      "#{location}/status"
    end

    conn = build_faraday("https://pdf-services.adobe.io")

    Rails.logger.info("[AdobePdfToExcelService] poll_start max_poll_seconds=#{max_poll_seconds} interval=#{poll_interval_seconds}")

    loop do
      elapsed = Time.current - started
      raise "Adobe exportpdf poll timeout after #{elapsed.to_i}s" if elapsed > max_poll_seconds

      res = with_retries("poll_status") do
        conn.get(status_url) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.headers["x-api-key"] = client_id
        end
      end

      raise "Adobe exportpdf status failed status=#{res.status} body=#{res.body}" unless res.status.to_i == 200

      data = JSON.parse(res.body.to_s)
      st = data["status"].to_s.downcase

      if st == "done"
        return data
      end

      if st == "failed"
        raise "Adobe exportpdf failed: #{data.to_json}"
      end

      sleep(poll_interval_seconds)
    end
  end

  def download_result(download_uri)
    Rails.logger.info("[AdobePdfToExcelService] download_result")
    conn = build_faraday("https://example.invalid")
    res = with_retries("download_result") { conn.get(download_uri) }

    raise "Adobe download failed status=#{res.status}" unless res.status.to_i == 200

    res.body
  end

  def extract_download_uri(status_payload)
    payload = status_payload.is_a?(Hash) ? status_payload : {}

    download_uri = payload["downloadUri"] || payload["dowloadUri"]
    download_uri ||= payload.dig("asset", "downloadUri")
    download_uri ||= payload.dig("asset", "uri")
    download_uri ||= payload.dig("result", "asset", "downloadUri")
    download_uri ||= payload.dig("result", "asset", "uri")
    download_uri ||= payload.dig("output", "asset", "downloadUri")
    download_uri ||= payload.dig("output", "asset", "uri")

    if download_uri.to_s.strip.empty?
      Rails.logger.warn("[AdobePdfToExcelService] missing_download_uri keys=#{payload.keys.sort.inspect} sample=#{payload.to_json.first(600)}")
    else
      masked = download_uri.to_s
      masked = masked[0, 80] + "..." if masked.length > 80
      Rails.logger.info("[AdobePdfToExcelService] download_uri_present uri=#{masked}")
    end

    download_uri
  end

  def write_output(bytes)
    file_path = @output_path.presence || "tmp/#{File.basename(@file_path, File.extname(@file_path))}.xlsx"
    FileUtils.mkdir_p(File.dirname(file_path))
    File.binwrite(file_path, bytes)
    file_path
  end
end
