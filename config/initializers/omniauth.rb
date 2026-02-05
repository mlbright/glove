# frozen_string_literal: true

# Configure OmniAuth to work correctly behind a reverse proxy
Rails.application.config.middleware.use OmniAuth::Builder do
  # Ensure OmniAuth uses the correct host from proxy headers
  # Note: Don't include SCRIPT_NAME here - Rails URL helpers already add the prefix
  OmniAuth.config.full_host = lambda do |env|
    scheme = env["HTTP_X_FORWARDED_PROTO"] || env["rack.url_scheme"]
    host = env["HTTP_X_FORWARDED_HOST"] || env["HTTP_HOST"]
    "#{scheme}://#{host}"
  end
end
