OpenAI.configure do |config|
  config.access_token = ENV["OPENAI_API_KEY"]

  request_timeout = ENV.fetch("OPENAI_REQUEST_TIMEOUT", "180").to_i
  open_timeout = ENV.fetch("OPENAI_OPEN_TIMEOUT", "30").to_i

  config.request_timeout = request_timeout if config.respond_to?(:request_timeout=)
  config.open_timeout = open_timeout if config.respond_to?(:open_timeout=)
end