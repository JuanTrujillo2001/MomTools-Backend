class ApplicationController < ActionController::API
  before_action :authenticate_user!

  attr_reader :current_user

  private

  def authenticate_user!
    token = bearer_token
    return render_unauthorized("Missing token") if token.blank?

    payload = JwtToken.decode(token)
    @current_user = User.find(payload[:user_id])
  rescue JWT::DecodeError, ActiveRecord::RecordNotFound
    render_unauthorized("Invalid token")
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    scheme, token = header.split(" ", 2)
    return nil unless scheme&.casecmp("Bearer")&.zero?

    token
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end
end
