# frozen_string_literal: true

# Configure session store to use persistent cookies
# This allows users to stay logged in even after closing the browser
# until they explicitly log out via the logout link
Rails.application.config.session_store :cookie_store,
  key: '_claudy_session',
  expire_after: 1.year, # Session persists for 1 year (or until explicit logout)
  secure: Rails.env.production?, # Use secure cookies in production
  same_site: :lax

