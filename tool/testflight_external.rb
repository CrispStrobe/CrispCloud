#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'open3'
require 'time'
require 'uri'
require_relative 'testflight_export_guard'

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
    unless uri.scheme == 'https' && uri.host == 'api.appstoreconnect.apple.com' &&
           uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?
      raise 'Refusing a request outside the App Store Connect HTTPS API origin'
    end
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
    # Apple measures lifetime as exp - iat, including the clock-skew allowance.
    claims = base64url(JSON.generate(iss: @issuer_id, iat: now - 20, exp: now + 600,
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

def run_testflight
  # A TestFlight distribution can reach France even when the storefront does not.
  # Validate the recorded channel/history review before any API mutation. This
  # cannot infer testers' locations; the release owner must substantiate the record.
  root = File.expand_path('..', __dir__)
  check = "import pathlib,sys; sys.path.insert(0,'tool'); " \
          "import apple_export_preflight as a; a.validate_policy(pathlib.Path('.'), submission=True); " \
          "print(a.release_version(pathlib.Path('.'))[0])"
  stdout, stderr, status = Open3.capture3('python3', '-c', check, chdir: root)
  abort "Apple export policy blocks TestFlight distribution: #{stderr.strip}" unless status.success?
  marketing_version = stdout.strip
  policy = JSON.parse(File.read(File.join(root, 'docs/apple-export-policy.json')))
  group_id = TestFlightExportGuard.selected_group_id(
    policy, requested_id: ENV.fetch('TESTFLIGHT_GROUP_ID', '').strip
  )

  client = AppStoreConnect.new(
    key_id: required_env('ASC_KEY_ID'),
    issuer_id: required_env('ASC_ISSUER_ID'),
    key_path: required_env('ASC_KEY_PATH')
  )
  bundle_id = ENV.fetch('ASC_BUNDLE_ID', 'com.CrispStrobe.cloud')
  abort 'TestFlight bundle ID differs from the reviewed export policy' unless bundle_id == policy.fetch('bundle_id')
  platform = ENV.fetch('ASC_PLATFORM', 'MAC_OS')
  abort 'Unsupported TestFlight application platform' unless %w[IOS MAC_OS].include?(platform)
  build_number = required_env('ASC_BUILD_NUMBER')
  requested_build_id = ENV.fetch('ASC_BUILD_ID', '').strip
  group_name = ENV.fetch('TESTFLIGHT_GROUP', '').strip
  what_to_test = ENV.fetch(
    'TESTFLIGHT_WHAT_TO_TEST',
    'Please verify launch reliability, sign-in, browsing, transfers, previews, and Finder integration on macOS.'
  )

  apps = client.get('/v1/apps', 'filter[bundleId]' => bundle_id, 'fields[apps]' => 'bundleId', 'limit' => 2).fetch('data')
  unless apps.one? && apps.first['type'] == 'apps' && apps.first.dig('attributes', 'bundleId') == bundle_id
    abort "App Store Connect must resolve exactly the reviewed app for #{bundle_id}"
  end
  app_id = apps.first.fetch('id')
  expected_app_id = ENV.fetch('ASC_APP_ID', '').strip
  if !expected_app_id.empty? && app_id != expected_app_id
    abort 'TestFlight app ID differs from ASC_APP_ID'
  end
  puts "App: #{bundle_id} (#{app_id})"

  deadline = Time.now + Integer(ENV.fetch('ASC_PROCESSING_TIMEOUT_SECONDS', '2400'))
  build = nil
  loop do
    query = {
      'filter[app]' => app_id,
      'filter[version]' => build_number,
      'filter[preReleaseVersion.platform]' => platform,
      'filter[preReleaseVersion.version]' => marketing_version,
      'fields[builds]' => 'version,uploadedDate,processingState,usesNonExemptEncryption,buildAudienceType',
      'limit' => 2
    }
    query['filter[id]'] = requested_build_id unless requested_build_id.empty?
    response = client.get('/v1/builds', query)
    build = TestFlightExportGuard.select_build!(response, build_number: build_number, requested_id: requested_build_id)
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
  guard = TestFlightExportGuard.new(client: client, policy: policy, app_id: app_id, build_id: build_id,
                                   build_number: build_number, marketing_version: marketing_version, platform: platform,
                                   group_id: group_id, group_name: group_name)
  group = guard.verify!
  puts "Reviewed external group: #{group.dig('attributes', 'name')} (#{group_id})"

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
    guard.post(
      '/v1/betaBuildLocalizations',
      data: {
        type: 'betaBuildLocalizations',
        attributes: { locale: 'en-US', whatsNew: what_to_test },
        relationships: { build: { data: linkage('builds', build_id) } }
      }
    )
    puts 'What to Test: created en-US localization'
  end

  # Never discover or create groups implicitly. The selected resource ID comes
  # from the reviewed allowlist; every mutation repeats its live checks.
  guard.post(
    "/v1/betaGroups/#{URI.encode_www_form_component(group_id)}/relationships/builds",
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
    submission = guard.post(
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
end

if $PROGRAM_NAME == __FILE__
  begin
    run_testflight
  rescue StandardError => error
    warn "TestFlight distribution stopped: #{error.message}"
    exit 1
  end
end
