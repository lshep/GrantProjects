require 'sinatra'
require_relative './core'
require 'pry' # remove when not needed

get '/' do
  'Nothing to see here'
end

post '/' do
  return Core.handle_post(request)
end

get '/acceptpolicies/:email/:action/:password' do
  return Core.accept_policies(params[:email], params[:action],
    params[:password])
end
