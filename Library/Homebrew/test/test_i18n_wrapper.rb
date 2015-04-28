require 'testing_env'

# These are integration tests to make sure the vendored i18n gem is doing
# everything it's expected to do, especially in 1.8.x Rubies that aren't
# officially supported by it anymore.
#
# TODO: Make some translation keys especially for these tests, in case these
# values get changed by someone unaware of these tests.
#
class I18nWrapperTests < Homebrew::TestCase
  def test_standard_lookup
    assert_equal "Closed pull requests:", t("utils.closed_pull_requests")
  end

  def test_basic_interpolation
    assert_equal "/bin/fnord is not executable", t("utils.not_executable", :path => "/bin/fnord")
  end

  def test_interpolation_and_pluralization
    assert_equal "1 second", t("utils.seconds", :count => 1)
    assert_equal "2 seconds", t("utils.seconds", :count => 2)
  end
end
