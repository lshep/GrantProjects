require 'sinatra'
require_relative './core'

get '/' do
  'Nothing to see here'
end

post '/add-entries' do
  status_code, response_body = Core.process_new_entries_payload(request.body.read)
  status status_code
  content_type :json
  response_body
end

post '/send-verification' do
  status_code, response_body = Core.process_verification_payload(request.body.read)
  status status_code
  content_type :json
  response_body
end

get '/acceptpolicies/:email/:action/:password' do
  return Core.accept_policies(params[:email], params[:action], params[:password])
end

