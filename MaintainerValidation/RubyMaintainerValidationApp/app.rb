require 'sinatra'
require_relative './core'

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

post '/add-entries' do
  status_code, response_body = Core.process_new_entries_payload(request.body.read)
  status status_code
  content_type :json
  response_body
end

get '/' do
  'Nothing to see here'
end

get '/acceptpolicies/:email/:action/:password' do
  return Core.accept_policies(params[:email], params[:action], params[:password])
end

get '/info/package/:pkg' do
  return Core.get_package_info(params[:pkg])
end

get '/info/name/:name' do
  return Core.get_name_info(params[:name])
end

get '/info/email/:email' do
  return Core.get_email_info(params[:email])
end

get '/info/valid/:email' do
  return Core.is_email_valid(params[:email])
end

get '/list/invalid/' do
  content_type :json
  return Core.list_invalid()
end

get '/list/needs-consent/' do
  content_type :json
  return Core.list_needs_consent()
end

get '/list/bademails/' do
  return Core.list_bad_emails()
end
