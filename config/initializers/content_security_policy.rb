# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    if Rails.env.development?
      # Allow @vite/client to hot reload javascript changes in development
      policy.script_src *policy.script_src, :unsafe_eval, "http://#{ ViteRuby.config.host_with_port }"

      # Allow @vite/client to hot reload style changes in development
      policy.style_src *policy.style_src, :unsafe_inline

      # Allow iframe embeds on www.les4sources.be and Tally forms
      policy.frame_ancestors :self, "https://www.les4sources.be", "https://tally.so"

      policy.connect_src :self,
                         # Allow @vite/client to hot reload CSS changes
                         "ws://#{ViteRuby.config.host}"

      policy.style_src :self,
                       :https,
                       # Allow @vite/client to hot reload style changes
                       :unsafe_inline

      policy.script_src :self,
                        :unsafe_inline,
                        # Allow Lookbook to build component previews
                        :unsafe_eval,
                        # Allow @vite/client to hot reload JavaScript changes
                        "http://#{ViteRuby.config.host_with_port}"
    else

#     policy.default_src :self, :https
#     policy.font_src    :self, :https, :data
#     policy.img_src     :self, :https, :data
#     policy.object_src  :none
#     policy.script_src  :self, :https

    # You may need to enable this in production as well depending on your setup.
#    policy.script_src *policy.script_src, :blob if Rails.env.test?

#     policy.style_src   :self, :https

#     # Specify URI for violation reports
#     # policy.report_uri "/csp-violation-report-endpoint"
    end
  end
#
#   # Generate session nonces for permitted importmap and inline scripts
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
#   config.content_security_policy_nonce_directives = %w(script-src)
#
#   # Report violations without enforcing the policy.
#   # config.content_security_policy_report_only = true
end
