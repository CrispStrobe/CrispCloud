#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

class AppStoreConnect
  API = 'https://api.appstoreconnect.apple.com'

  def initialize(key_id:, issuer_id:, key_path:)
    @key_id = key_id
    @issuer_id = issuer_id
    @key = OpenSSL::PKey.read(File.read(key_path))
  end

  def get(path, query = {})
    request(Net::HTTP::Get, path, query: query)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, body: body)
  end

  private

  def request(request_class, path, query: {}, body: nil)
    uri = URI.join(API, path)
    uri.query = URI.encode_www_form(query) unless query.empty?
    request = request_class.new(uri)
    request['Authorization'] = "Bearer #{jwt}"
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body) if body
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.open_timeout = 30
      http.read_timeout = 60
      http.request(request)
    end
    if response.code.to_i.between?(200, 299)
      return {} if response.body.nil? || response.body.empty?
      return JSON.parse(response.body)
    end

    details = begin
      JSON.parse(response.body).fetch('errors', []).map do |error|
        [error['code'], error['title'], error['detail']].compact.join(': ')
      end.join('\n')
    rescue JSON::ParserError
      response.body
    end
    raise "App Store Connect #{request.method} #{uri.path} failed (#{response.code}):\n#{details}"
  end

  def jwt
    now = Time.now.to_i
    header = base64url(JSON.generate(alg: 'ES256', kid: @key_id, typ: 'JWT'))
    claims = base64url(JSON.generate(iss: @issuer_id, iat: now - 20, exp: now + 1_200,
                                     aud: 'appstoreconnect-v1'))
    signing_input = "#{header}.#{claims}"
    der_signature = @key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
    sequence = OpenSSL::ASN1.decode(der_signature)
    raw_signature = sequence.value.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
    "#{signing_input}.#{base64url(raw_signature)}"
  end

  def base64url(value)
    Base64.urlsafe_encode64(value, padding: false)
  end
end

def required_env(name)
  value = ENV[name]
  abort "Missing required environment variable #{name}" if value.nil? || value.empty?
  value
end

def linkage(type, id)
  { type: type, id: id }
end

client = AppStoreConnect.new(
  key_id: required_env('ASC_KEY_ID'),
  issuer_id: required_env('ASC_ISSUER_ID'),
  key_path: required_env('ASC_KEY_PATH')
)
bundle_id = ENV.fetch('ASC_BUNDLE_ID', 'com.CrispStrobe.cloud')
platform = ENV.fetch('ASC_PLATFORM', 'MAC_OS')
build_number = required_env('ASC_BUILD_NUMBER')
group_name = ENV.fetch('TESTFLIGHT_GROUP', '').strip
what_to_test = ENV.fetch(
  'TESTFLIGHT_WHAT_TO_TEST',
  'Please verify launch reliability, sign-in, browsing, transfers, previews, and Finder integration on macOS.'
)

apps = client.get('/v1/apps', 'filter[bundleId]' => bundle_id, 'limit' => 2).fetch('data')
abort "No App Store Connect app found for #{bundle_id}" if apps.empty?
abort "Multiple App Store Connect apps found for #{bundle_id}" unless apps.one?
app_id = apps.first.fetch('id')
puts "App: #{bundle_id} (#{app_id})"

deadline = Time.now + Integer(ENV.fetch('ASC_PROCESSING_TIMEOUT_SECONDS', '2400'))
build = nil
loop do
  builds = client.get(
    '/v1/builds',
    'filter[app]' => app_id,
    'filter[version]' => build_number,
    'filter[preReleaseVersion.platform]' => platform,
    'fields[builds]' => 'version,uploadedDate,processingState,usesNonExemptEncryption,buildAudienceType',
    'limit' => 10
  ).fetch('data')
  build = builds.max_by { |item| item.dig('attributes', 'uploadedDate').to_s }
  if build
    state = build.dig('attributes', 'processingState')
    puts "Build #{build_number}: #{state} (#{build.fetch('id')})"
    break if state == 'VALID'
    abort "Apple marked build #{build_number} as #{state}" if %w[FAILED INVALID].include?(state)
  else
    puts "Build #{build_number}: not visible yet"
  end
  abort "Timed out waiting for Apple to process build #{build_number}" if Time.now >= deadline
  sleep 30
end
build_id = build.fetch('id')

localizations = client.get(
  '/v1/betaBuildLocalizations',
  'filter[build]' => build_id,
  'fields[betaBuildLocalizations]' => 'locale,whatsNew',
  'limit' => 50
).fetch('data')
english = localizations.find { |item| item.dig('attributes', 'locale') == 'en-US' }
if english
  puts 'What to Test: existing en-US localization retained'
else
  client.post(
    '/v1/betaBuildLocalizations',
    data: {
      type: 'betaBuildLocalizations',
      attributes: { locale: 'en-US', whatsNew: what_to_test },
      relationships: { build: { data: linkage('builds', build_id) } }
    }
  )
  puts 'What to Test: created en-US localization'
end

groups = client.get(
  '/v1/betaGroups',
  'filter[app]' => app_id,
  'fields[betaGroups]' => 'name,isInternalGroup,hasAccessToAllBuilds',
  'limit' => 200
).fetch('data')
external_groups = groups.reject { |item| item.dig('attributes', 'isInternalGroup') }
puts "External groups: #{external_groups.map { |item| item.dig('attributes', 'name') }.join(', ')}"

group = if group_name.empty?
          external_groups.one? ? external_groups.first : nil
        else
          external_groups.find { |item| item.dig('attributes', 'name') == group_name }
        end

if group.nil? && external_groups.empty? && group_name.empty?
  created = client.post(
    '/v1/betaGroups',
    data: {
      type: 'betaGroups',
      attributes: { name: 'External Testers', isInternalGroup: false },
      relationships: { app: { data: linkage('apps', app_id) } }
    }
  )
  group = created.fetch('data')
  puts "Created external group: #{group.dig('attributes', 'name')}"
elsif group.nil?
  available = external_groups.map { |item| item.dig('attributes', 'name') }.join(', ')
  abort(group_name.empty? ?
    "More than one external group exists; set TESTFLIGHT_GROUP to one of: #{available}" :
    "External group '#{group_name}' not found; available groups: #{available}")
end

group_id = group.fetch('id')
client.post(
  "/v1/betaGroups/#{group_id}/relationships/builds",
  data: [linkage('builds', build_id)]
)
puts "Assigned build #{build_number} to external group '#{group.dig('attributes', 'name')}'"

submissions = client.get(
  '/v1/betaAppReviewSubmissions',
  'filter[build]' => build_id,
  'fields[betaAppReviewSubmissions]' => 'betaReviewState,submittedDate',
  'limit' => 10
).fetch('data')
if submissions.empty?
  submission = client.post(
    '/v1/betaAppReviewSubmissions',
    data: {
      type: 'betaAppReviewSubmissions',
      relationships: { build: { data: linkage('builds', build_id) } }
    }
  ).fetch('data')
  puts "Beta review submitted: #{submission.dig('attributes', 'betaReviewState')}"
else
  state = submissions.max_by { |item| item.dig('attributes', 'submittedDate').to_s }
                     .dig('attributes', 'betaReviewState')
  puts "Beta review already exists: #{state}"
end
