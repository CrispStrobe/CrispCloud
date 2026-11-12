# frozen_string_literal: true

require 'minitest/autorun'
# Requiring the CLI is intentional: it must not read account keys or run work.
require_relative 'testflight_external'

class TestFlightExportGuardTest < Minitest::Test
  class FakeClient
    attr_reader :posts, :gets
    attr_accessor :group, :build, :declaration, :prerelease

    def initialize
      @posts, @gets = [], []
      app = { 'type' => 'apps', 'id' => 'app-1' }
      @group = { 'type' => 'betaGroups', 'id' => 'group-1',
                 'attributes' => { 'name' => 'Reviewed testers', 'isInternalGroup' => false, 'publicLinkEnabled' => false },
                 'relationships' => { 'app' => { 'data' => app } } }
      @build = { 'type' => 'builds', 'id' => 'build-1',
                 'attributes' => { 'version' => '10', 'processingState' => 'VALID', 'usesNonExemptEncryption' => false },
                 'relationships' => { 'app' => { 'data' => app } } }
      @prerelease = { 'type' => 'preReleaseVersions', 'id' => 'prerelease-1',
                      'attributes' => { 'version' => '1.1.0', 'platform' => 'MAC_OS' } }
      @declaration = { 'type' => 'appEncryptionDeclarations', 'id' => 'declaration-1',
                       'attributes' => { 'appEncryptionDeclarationState' => 'APPROVED', 'codeValue' => 'issued-code',
                                         'platform' => 'MAC_OS', 'usesEncryption' => true, 'exempt' => false,
                                         'availableOnFrenchStore' => true } }
    end

    def get(path, _query = {})
      @gets << path
      data = case path
             when '/v1/betaGroups/group-1' then @group
             when '/v1/builds/build-1' then @build
             when '/v1/builds/build-1/preReleaseVersion' then @prerelease
             when '/v1/builds/build-1/appEncryptionDeclaration' then @declaration
             else raise "Unexpected read #{path}"
             end
      { 'data' => Marshal.load(Marshal.dump(data)) }
    end

    def post(path, body)
      @posts << [path, body]
      { 'data' => { 'id' => 'fixture-result' } }
    end
  end

  def setup
    @policy = { 'uses_non_exempt_encryption' => false,
                'documentation' => { 'status' => 'not_required', 'compliance_code' => nil },
                'testflight' => { 'distribution_review' => 'no_france',
                                  'reference' => 'Fixture review of the intended group recipients',
                                  'external_group_ids' => ['group-1'], 'allow_public_links' => false } }
    @client = FakeClient.new
  end

  def guard
    TestFlightExportGuard.new(client: @client, policy: @policy, app_id: 'app-1', build_id: 'build-1',
                             build_number: '10', marketing_version: '1.1.0', platform: 'MAC_OS', group_id: 'group-1')
  end

  def localization
    { data: { type: 'betaBuildLocalizations', attributes: { locale: 'en-US', whatsNew: 'Fixture' },
              relationships: { build: { data: { type: 'builds', id: 'build-1' } } } } }
  end

  def assignment
    { data: [{ type: 'builds', id: 'build-1' }] }
  end

  def submission
    { data: { type: 'betaAppReviewSubmissions',
              relationships: { build: { data: { type: 'builds', id: 'build-1' } } } } }
  end

  def approve_france(public_links: false)
    @policy['uses_non_exempt_encryption'] = true
    @policy['documentation'] = { 'status' => 'approved', 'compliance_code' => 'issued-code' }
    @policy['testflight']['distribution_review'] = 'france_covered'
    @policy['testflight']['allow_public_links'] = public_links
    @client.build['attributes']['usesNonExemptEncryption'] = true
  end

  def test_pending_review_stops_before_any_api_read_or_write
    @policy['testflight']['distribution_review'] = 'pending'
    assert_raises(TestFlightExportGuard::Error) { guard }
    assert_empty @client.gets
    assert_empty @client.posts
  end

  def test_changed_crypto_requires_a_new_documentation_review_before_distribution
    [nil, {}, { 'status' => 'unreviewed' }, { 'status' => 'unknown' }].each do |documentation|
      @policy['documentation'] = documentation
      error = assert_raises(TestFlightExportGuard::Error) { guard }
      assert_match(/documentation review is pending/, error.message)
      assert_empty @client.gets
      assert_empty @client.posts
    end
  end

  def test_false_answer_cannot_claim_an_approved_declaration_or_code
    [{ 'status' => 'approved', 'compliance_code' => 'issued-code' },
     { 'status' => 'not_required', 'compliance_code' => 'invented-code' }].each do |documentation|
      @policy['documentation'] = documentation
      assert_raises(TestFlightExportGuard::Error) { guard }
      assert_empty @client.gets
      assert_empty @client.posts
    end
  end

  def test_review_requires_evidence_unique_group_ids_and_explicit_link_policy
    cases = [{ 'reference' => nil }, { 'external_group_ids' => [] },
             { 'external_group_ids' => ['group-1', 'group-1'] }, { 'external_group_ids' => ['../other'] },
             { 'allow_public_links' => nil }]
    cases.each do |changes|
      policy = Marshal.load(Marshal.dump(@policy))
      policy['testflight'].merge!(changes)
      assert_raises(TestFlightExportGuard::Error) { TestFlightExportGuard.validate_policy!(policy) }
    end
  end

  def test_only_exact_reviewed_group_ids_can_be_selected
    assert_equal 'group-1', TestFlightExportGuard.selected_group_id(@policy)
    assert_raises(TestFlightExportGuard::Error) { TestFlightExportGuard.selected_group_id(@policy, requested_id: 'other') }
    @policy['testflight']['external_group_ids'] << 'group-2'
    assert_raises(TestFlightExportGuard::Error) { TestFlightExportGuard.selected_group_id(@policy) }
    assert_equal 'group-2', TestFlightExportGuard.selected_group_id(@policy, requested_id: 'group-2')
  end

  def test_no_documentation_route_cannot_approve_french_testers_or_public_links
    @policy['testflight']['distribution_review'] = 'france_covered'
    assert_raises(TestFlightExportGuard::Error) { guard }
    @policy['testflight']['distribution_review'] = 'no_france'
    @policy['testflight']['allow_public_links'] = true
    assert_raises(TestFlightExportGuard::Error) { guard }
  end

  def test_public_unknown_and_numeric_link_flags_stop_even_localization_mutations
    [true, nil, 0, 'false'].each do |flag|
      @client.group['attributes']['publicLinkEnabled'] = flag
      assert_raises(TestFlightExportGuard::Error) { guard.post('/v1/betaBuildLocalizations', localization) }
      assert_empty @client.posts
    end
  end

  def test_link_enabled_between_mutations_stops_the_next_write
    checked = guard
    checked.post('/v1/betaBuildLocalizations', localization)
    assert_equal 1, @client.posts.length
    @client.group['attributes']['publicLinkEnabled'] = true
    assert_raises(TestFlightExportGuard::Error) do
      checked.post('/v1/betaGroups/group-1/relationships/builds', assignment)
    end
    assert_equal 1, @client.posts.length
  end

  def test_every_supported_mutation_repeats_live_checks
    checked = guard
    checked.post('/v1/betaBuildLocalizations', localization)
    checked.post('/v1/betaGroups/group-1/relationships/builds', assignment)
    checked.post('/v1/betaAppReviewSubmissions', submission)
    assert_equal 3, @client.posts.length
    assert_equal 3, @client.gets.count('/v1/betaGroups/group-1')
    assert_equal 3, @client.gets.count('/v1/builds/build-1')
    assert_equal 3, @client.gets.count('/v1/builds/build-1/preReleaseVersion')
  end

  def test_group_must_be_external_and_belong_to_the_same_app
    @client.group['attributes']['isInternalGroup'] = true
    assert_raises(TestFlightExportGuard::Error) { guard.verify! }
    @client.group['attributes']['isInternalGroup'] = false
    @client.group['relationships']['app']['data'] = { 'type' => 'apps', 'id' => 'other-app' }
    assert_raises(TestFlightExportGuard::Error) { guard.verify! }
    assert_empty @client.posts
  end

  def test_optional_name_check_cannot_select_an_unreviewed_id
    checked = TestFlightExportGuard.new(client: @client, policy: @policy, app_id: 'app-1', build_id: 'build-1',
                                       build_number: '10', marketing_version: '1.1.0', platform: 'MAC_OS',
                                       group_id: 'group-1', group_name: 'Different group')
    assert_raises(TestFlightExportGuard::Error) { checked.verify! }
  end

  def test_uploaded_build_must_match_identity_state_and_encryption
    original = Marshal.load(Marshal.dump(@client.build))
    [{ 'version' => '11' }, { 'processingState' => 'PROCESSING' }, { 'usesNonExemptEncryption' => true },
     { 'usesNonExemptEncryption' => nil }].each do |changes|
      @client.build = Marshal.load(Marshal.dump(original))
      @client.build['attributes'].merge!(changes)
      assert_raises(TestFlightExportGuard::Error) { guard.post('/v1/betaBuildLocalizations', localization) }
    end
    @client.build = Marshal.load(Marshal.dump(original))
    @client.build['relationships']['app']['data'] = { 'type' => 'apps', 'id' => 'other-app' }
    assert_raises(TestFlightExportGuard::Error) { guard.verify! }
    assert_empty @client.posts
  end

  def test_approved_french_route_can_explicitly_allow_public_links
    approve_france(public_links: true)
    @client.group['attributes']['publicLinkEnabled'] = true
    guard.post('/v1/betaGroups/group-1/relationships/builds', assignment)
    assert_equal 1, @client.posts.length
  end

  def test_build_platform_and_marketing_version_are_read_not_inferred_from_filters
    @client.prerelease['attributes']['platform'] = 'IOS'
    assert_raises(TestFlightExportGuard::Error) { guard.post('/v1/betaBuildLocalizations', localization) }
    @client.prerelease['attributes']['platform'] = 'MAC_OS'
    @client.prerelease['attributes']['version'] = '1.0.0'
    assert_raises(TestFlightExportGuard::Error) { guard.post('/v1/betaBuildLocalizations', localization) }
    assert_empty @client.posts
  end

  def candidate(id, number = '10')
    { 'type' => 'builds', 'id' => id, 'attributes' => { 'version' => number } }
  end

  def candidates(*builds)
    { 'data' => builds, 'links' => { 'next' => nil }, 'meta' => { 'paging' => { 'total' => builds.length } } }
  end

  def test_build_selector_waits_for_none_and_accepts_one_complete_candidate
    assert_nil TestFlightExportGuard.select_build!(candidates, build_number: '10')
    selected = TestFlightExportGuard.select_build!(candidates(candidate('first')), build_number: '10')
    assert_equal 'first', selected['id']
  end

  def test_build_selector_never_selects_the_newest_of_multiple_candidates
    response = candidates(candidate('old'), candidate('new'))
    response['data'][1]['attributes']['uploadedDate'] = '2099-01-01T00:00:00Z'
    assert_raises(TestFlightExportGuard::Error) { TestFlightExportGuard.select_build!(response, build_number: '10') }
    selected = TestFlightExportGuard.select_build!(response, build_number: '10', requested_id: 'old')
    assert_equal 'old', selected['id']
    assert_raises(TestFlightExportGuard::Error) do
      TestFlightExportGuard.select_build!(response, build_number: '10', requested_id: 'absent')
    end
  end

  def test_build_selector_rejects_partial_pages_incorrect_totals_and_duplicate_ids
    partial = candidates(candidate('first'))
    partial['links']['next'] = 'https://api.appstoreconnect.apple.com/v1/builds?cursor=second'
    assert_raises(TestFlightExportGuard::Error) { TestFlightExportGuard.select_build!(partial, build_number: '10') }
    partial['links']['next'] = nil
    partial['meta']['paging']['total'] = 2
    assert_raises(TestFlightExportGuard::Error) { TestFlightExportGuard.select_build!(partial, build_number: '10') }
    assert_raises(TestFlightExportGuard::Error) do
      TestFlightExportGuard.select_build!(candidates(candidate('same'), candidate('same')), build_number: '10', requested_id: 'same')
    end
    assert_raises(TestFlightExportGuard::Error) do
      TestFlightExportGuard.select_build!(candidates(candidate('wrong', '11')), build_number: '10')
    end
  end

  def test_french_route_still_rejects_unapproved_or_mismatched_declarations
    approve_france
    original = Marshal.load(Marshal.dump(@client.declaration))
    [{ 'availableOnFrenchStore' => false }, { 'appEncryptionDeclarationState' => 'EXPIRED' },
     { 'codeValue' => 'different-code' }, { 'platform' => 'IOS' }, { 'usesEncryption' => false },
     { 'exempt' => true }].each do |changes|
      @client.declaration = Marshal.load(Marshal.dump(original))
      @client.declaration['attributes'].merge!(changes)
      assert_raises(TestFlightExportGuard::Error) { guard.post('/v1/betaAppReviewSubmissions', submission) }
    end
    assert_empty @client.posts
  end

  def test_french_approval_without_explicit_public_link_permission_is_insufficient
    approve_france
    @client.group['attributes']['publicLinkEnabled'] = true
    assert_raises(TestFlightExportGuard::Error) { guard.verify! }
  end

  def test_group_creation_and_writes_for_other_builds_or_groups_are_forbidden
    checked = guard
    assert_raises(TestFlightExportGuard::Error) { checked.post('/v1/betaGroups', data: { type: 'betaGroups' }) }
    assert_raises(TestFlightExportGuard::Error) { checked.post('/v1/betaGroups/other/relationships/builds', assignment) }
    wrong = localization
    wrong[:data][:relationships][:build][:data][:id] = 'other-build'
    assert_raises(TestFlightExportGuard::Error) { checked.post('/v1/betaBuildLocalizations', wrong) }
    assert_empty @client.posts
  end

  def test_jwt_lifetime_remains_within_apple_limit_including_clock_skew
    client = AppStoreConnect.allocate
    client.instance_variable_set(:@key_id, 'fixture-key')
    client.instance_variable_set(:@issuer_id, 'fixture-issuer')
    client.instance_variable_set(:@key, OpenSSL::PKey::EC.generate('prime256v1'))
    token = client.send(:jwt)
    claims = JSON.parse(Base64.urlsafe_decode64(token.split('.')[1]))
    assert_operator claims.fetch('exp') - claims.fetch('iat'), :<=, 1200
    assert_equal 'appstoreconnect-v1', claims.fetch('aud')
    assert_equal 64, Base64.urlsafe_decode64(token.split('.')[2]).bytesize
  end

  def test_cross_origin_request_fails_before_accessing_a_signing_key
    client = AppStoreConnect.allocate
    error = assert_raises(RuntimeError) { client.get('https://attacker.invalid/v1/apps') }
    assert_match(/outside the App Store Connect/, error.message)
  end
end
