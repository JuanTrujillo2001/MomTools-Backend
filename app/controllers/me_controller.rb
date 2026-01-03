class MeController < ApplicationController
  def show
    render json: { id: current_user.id, email: current_user.email, name: current_user.name }
  end
end
