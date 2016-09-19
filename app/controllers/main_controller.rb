class MainController < ApplicationController
	skip_before_filter :is_signed_in, :only => [:cookie_hack, :home]

  def home
  end

  def cookie_hack
  	cookies[:email] = params[:email]
  	render json: "email set to #{params[:email]}"
  end
end
