class ApplicationMailer < ActionMailer::Base
  default from: "\"Les 4 Sources\" <#{ENV['DEFAULT_FROM_EMAIL']}>"
  default bcc: ENV.fetch('DEFAULT_BCC_EMAIL', nil)
  layout "mailer"
end
