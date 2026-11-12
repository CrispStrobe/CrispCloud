# frozen_string_literal: true

require 'json'
require 'uri'

# A storefront restriction does not restrict TestFlight recipients. This guard
# requires a separate human review of the selected external group IDs. Apple
# does not expose a reliable tester-country field; an email address or device
# criterion must never be treated as evidence that a tester is outside France.
#
# API fields: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-betagroups-_id_
# Public links: https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers
class TestFlightExportGuard
  class Error < StandardError; end

  def self.text?(value)
    value.is_a?(String) && !value.strip.empty?
  end

  def self.identifier?(value)
    text?(value) && value == value.strip && !value.match?(/[\s\/\\?#]/) && !%w[. ..].include?(value)
  end

  def self.validate_policy!(policy)
    review = policy['testflight']
    unless review.is_a?(Hash) && %w[no_france france_covered].include?(review['distribution_review'])
      raise Error, 'TestFlight distribution review is pending: record intended recipients and exact external group IDs before distribution'
    end
    raise Error, 'TestFlight distribution review needs an evidence reference' unless text?(review['reference'])
    ids = review['external_group_ids']
    unless ids.is_a?(Array) && !ids.empty? && ids.all? { |id| identifier?(id) } && ids.uniq.length == ids.length
      raise Error, 'TestFlight requires a nonempty unique allowlist of reviewed external group IDs'
    end
    unless review['allow_public_links'] == true || review['allow_public_links'] == false
      raise Error, 'TestFlight allow_public_links must be an explicit Boolean'
    end
    non_exempt = policy['uses_non_exempt_encryption']
    unless non_exempt == true || non_exempt == false
      raise Error, 'TestFlight policy needs an explicit encryption answer'
    end
    documentation = policy['documentation']
    unless documentation.is_a?(Hash) && %w[not_required approved].include?(documentation['status'])
      raise Error, 'TestFlight encryption documentation review is pending: record the completed Apple questionnaire result before distribution'
    end
    if non_exempt == false && (documentation['status'] != 'not_required' || !documentation['compliance_code'].nil?)
      raise Error, 'The no-documentation TestFlight answer requires a reviewed not_required result without an Apple code'
    end
    if non_exempt && (policy.dig('documentation', 'status') != 'approved' ||
                      !text?(policy.dig('documentation', 'compliance_code')))
      raise Error, 'Non-exempt TestFlight distribution requires an approved Apple code'
    end
    if review['distribution_review'] == 'no_france'
      raise Error, 'A no-France TestFlight review cannot allow public links' unless review['allow_public_links'] == false
    elsif non_exempt != true || policy.dig('documentation', 'status') != 'approved' ||
          !text?(policy.dig('documentation', 'compliance_code'))
      raise Error, 'French TestFlight distribution requires the Apple-approved documentation and code route'
    end
    if non_exempt == false && review['distribution_review'] != 'no_france'
      raise Error, 'The no-documentation answer cannot cover French TestFlight distribution'
    end
    review
  end

  def self.selected_group_id(policy, requested_id: '')
    review = validate_policy!(policy)
    ids = review.fetch('external_group_ids')
    if requested_id.empty?
      raise Error, 'More than one group ID is reviewed; set TESTFLIGHT_GROUP_ID explicitly' unless ids.one?
      return ids.first
    end
    raise Error, 'TESTFLIGHT_GROUP_ID is not in the reviewed external-group allowlist' unless ids.include?(requested_id)
    requested_id
  end

  # Never infer identity from the newest result or a partial page. An exact
  # requested ID can disambiguate a complete response; otherwise require one
  # candidate. Callers also filter by app, marketing version and platform.
  def self.select_build!(response, build_number:, requested_id: '')
    unless requested_id.empty? || identifier?(requested_id)
      raise Error, 'ASC_BUILD_ID must be an exact App Store Connect resource ID'
    end
    builds, links = response['data'], response['links']
    unless builds.is_a?(Array) && links.is_a?(Hash)
      raise Error, 'Cannot select a TestFlight build from an incomplete API response'
    end
    unless links['next'].nil?
      raise Error, 'TestFlight build candidates span multiple pages; provide ASC_BUILD_ID instead of selecting a partial result'
    end
    meta = response['meta']
    if !meta.nil? && (!meta.is_a?(Hash) || (!meta['paging'].nil? && !meta['paging'].is_a?(Hash)))
      raise Error, 'Invalid TestFlight build pagination metadata'
    end
    total = meta&.dig('paging', 'total')
    if !total.nil? && (!total.is_a?(Integer) || total != builds.length)
      raise Error, 'TestFlight build response does not contain every reported candidate'
    end
    unless builds.all? { |build| build.is_a?(Hash) && build['type'] == 'builds' && identifier?(build['id']) &&
                         build.dig('attributes', 'version') == build_number }
      raise Error, 'TestFlight build candidates do not match the requested build number'
    end
    if builds.map { |build| build['id'] }.uniq.length != builds.length
      raise Error, 'TestFlight build response contains duplicate IDs'
    end
    return nil if builds.empty?
    unless requested_id.empty?
      exact = builds.select { |build| build['id'] == requested_id }
      raise Error, 'ASC_BUILD_ID does not identify a returned candidate for this release' unless exact.one?
      return exact.first
    end
    raise Error, 'Multiple TestFlight builds match; provide ASC_BUILD_ID explicitly' unless builds.one?
    builds.first
  end

  def initialize(client:, policy:, app_id:, build_id:, build_number:, marketing_version:, platform:, group_id:, group_name: '')
    self.class.validate_policy!(policy)
    unless [app_id, build_id, group_id].all? { |id| self.class.identifier?(id) }
      raise Error, 'TestFlight app, build and group IDs must be explicit resource IDs'
    end
    raise Error, 'Unsupported TestFlight application platform' unless %w[IOS MAC_OS].include?(platform)
    raise Error, 'The reviewed marketing version is required' unless self.class.text?(marketing_version)
    @client, @policy = client, policy
    @app_id, @build_id, @build_number, @platform = app_id, build_id, build_number, platform
    @marketing_version = marketing_version
    @group_id, @group_name = group_id, group_name
  end

  def encoded(id)
    URI.encode_www_form_component(id)
  end

  def verify!
    review = self.class.validate_policy!(@policy)
    unless review.fetch('external_group_ids').include?(@group_id)
      raise Error, 'Selected TestFlight group is no longer in the reviewed allowlist'
    end
    group = @client.get(
      "/v1/betaGroups/#{encoded(@group_id)}",
      'fields[betaGroups]' => 'name,isInternalGroup,publicLinkEnabled,app',
      'include' => 'app', 'fields[apps]' => 'bundleId'
    ).fetch('data')
    unless group.is_a?(Hash) && group['type'] == 'betaGroups' && group['id'] == @group_id &&
           group.dig('relationships', 'app', 'data', 'type') == 'apps' &&
           group.dig('relationships', 'app', 'data', 'id') == @app_id &&
           group.dig('attributes', 'isInternalGroup') == false
      raise Error, 'The selected ID must identify an external TestFlight group of this app'
    end
    if !@group_name.empty? && group.dig('attributes', 'name') != @group_name
      raise Error, 'The selected TestFlight group ID does not match TESTFLIGHT_GROUP'
    end
    public_link = group.dig('attributes', 'publicLinkEnabled')
    unless public_link == false || (public_link == true && review['allow_public_links'] == true &&
                                    review['distribution_review'] == 'france_covered')
      raise Error, 'Public TestFlight link is enabled or unknown without reviewed French coverage and explicit permission'
    end

    build = @client.get(
      "/v1/builds/#{encoded(@build_id)}",
      'fields[builds]' => 'version,processingState,usesNonExemptEncryption,app',
      'include' => 'app', 'fields[apps]' => 'bundleId'
    ).fetch('data')
    unless build.is_a?(Hash) && build['type'] == 'builds' && build['id'] == @build_id &&
           build.dig('relationships', 'app', 'data', 'type') == 'apps' &&
           build.dig('relationships', 'app', 'data', 'id') == @app_id &&
           build.dig('attributes', 'version') == @build_number &&
           build.dig('attributes', 'processingState') == 'VALID' &&
           build.dig('attributes', 'usesNonExemptEncryption') == @policy.fetch('uses_non_exempt_encryption')
      raise Error, 'Uploaded TestFlight build identity, processing state or encryption answer differs from the review'
    end
    prerelease = @client.get(
      "/v1/builds/#{encoded(@build_id)}/preReleaseVersion", 'fields[preReleaseVersions]' => 'version,platform'
    ).fetch('data')
    unless prerelease.is_a?(Hash) && prerelease['type'] == 'preReleaseVersions' &&
           prerelease.dig('attributes', 'platform') == @platform &&
           prerelease.dig('attributes', 'version') == @marketing_version
      raise Error, 'Uploaded TestFlight build platform or marketing version differs from the reviewed release'
    end
    if @policy.fetch('uses_non_exempt_encryption')
      declaration = @client.get("/v1/builds/#{encoded(@build_id)}/appEncryptionDeclaration").fetch('data')
      attributes = declaration.is_a?(Hash) ? declaration.fetch('attributes', {}) : {}
      unless declaration.is_a?(Hash) && declaration['type'] == 'appEncryptionDeclarations' &&
             attributes['appEncryptionDeclarationState'] == 'APPROVED' &&
             attributes['codeValue'] == @policy.dig('documentation', 'compliance_code') &&
             attributes['usesEncryption'] == true && attributes['exempt'] == false
        raise Error, 'TestFlight build must have the matching approved non-exempt Apple declaration'
      end
      declared_platform = attributes['platform']
      if !declared_platform.nil? && declared_platform.to_s.upcase != @platform
        raise Error, 'TestFlight encryption declaration platform does not match the selected build'
      end
      if review['distribution_review'] == 'france_covered' && attributes['availableOnFrenchStore'] != true
        raise Error, 'The approved declaration does not cover French TestFlight distribution'
      end
    end
    group
  end

  # Re-read live group/build/approval state before EACH mutation. In particular,
  # a link enabled after the initial selection must stop subsequent writes.
  # This is a preflight, not an atomic transaction with App Store Connect.
  def post(path, body)
    data = JSON.parse(JSON.generate(body)).fetch('data')
    build_link = { 'type' => 'builds', 'id' => @build_id }
    case path
    when '/v1/betaBuildLocalizations'
      unless data.is_a?(Hash) && data['type'] == 'betaBuildLocalizations' &&
             data.dig('relationships', 'build', 'data') == build_link
        raise Error, 'Localization mutation does not target the reviewed TestFlight build'
      end
    when "/v1/betaGroups/#{encoded(@group_id)}/relationships/builds"
      raise Error, 'Group mutation must assign only the reviewed build' unless data == [build_link]
    when '/v1/betaAppReviewSubmissions'
      unless data.is_a?(Hash) && data['type'] == 'betaAppReviewSubmissions' &&
             data.dig('relationships', 'build', 'data') == build_link
        raise Error, 'Review mutation does not target the reviewed TestFlight build'
      end
    else
      raise Error, 'This TestFlight guard does not allow group creation or other unreviewed mutations'
    end
    verify!
    @client.post(path, body)
  end
end
