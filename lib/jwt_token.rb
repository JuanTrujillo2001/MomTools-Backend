module JwtToken
  ALGORITHM = "HS256"

  def self.encode(payload, exp: 24.hours.from_now)
    payload = payload.dup
    payload[:exp] = exp.to_i
    JWT.encode(payload, secret_key, ALGORITHM)
  end

  def self.decode(token)
    decoded, = JWT.decode(token, secret_key, true, { algorithm: ALGORITHM })
    decoded.with_indifferent_access
  end

  def self.secret_key
    ENV.fetch("JWT_SECRET") { Rails.application.secret_key_base }
  end
end
