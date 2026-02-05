# frozen_string_literal: true

# Middleware to set SCRIPT_NAME from the X-Script-Name header
# This allows reverse proxies (like Caddy) to inform Rails of the subpath
module Rack
  class ScriptNameFromHeader
    def initialize(app, header_name = "HTTP_X_SCRIPT_NAME")
      @app = app
      @header_name = header_name
    end

    def call(env)
      if (script_name = env[@header_name])
        env["SCRIPT_NAME"] = script_name
        env["PATH_INFO"] = env["PATH_INFO"].to_s
      end
      @app.call(env)
    end
  end
end
