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
  begin
    payload = request.body.read
    base_url = request.base_url
    status_code, response_body = Core.process_verification_payload(payload, base_url)
    status status_code
    content_type :json
    response_body
  rescue => e
    puts "Error: #{e.message}"
    status 500
    { error: e.message }.to_json
  end
end

get '/acceptpolicies/:email/:action/:password' do
  return Core.accept_policies(params[:email], params[:action], params[:password])
end

