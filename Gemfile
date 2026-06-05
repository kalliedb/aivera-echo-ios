source "https://rubygems.org"

gem "fastlane"
gem "xcodeproj"

# Transitive deps fastlane's runtime requires but doesn't list explicitly.
# Without these, bundler in frozen mode raises:
#   "<gem> is not part of the bundle. Add it to your Gemfile."
gem "multi_json"   # representable -> google-apis-core -> playcustomapp loader chain
gem "rexml"        # extracted from Ruby default gems in 3.3+
gem "json"
