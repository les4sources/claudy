class RevenueShareMailer < ApplicationMailer
  # Le relevé de reversement envoyé aux propriétaires d'un hébergement partagé
  # (issue #247).
  #
  # HTML et lien à jeton, comme les décomptes sourciers : aucune gem PDF au
  # Gemfile, et « Imprimer → Enregistrer en PDF » du navigateur suffit à la
  # famille qui veut archiver son trimestre.
  def statement(statement)
    @statement = statement
    @agreement = statement.revenue_share_agreement
    @lines = statement.revenue_share_statement_lines.chronological
    @statement_url = public_revenue_share_statement_url(
      statement.token, host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
    )

    mail(to: @agreement.beneficiary_email, subject: @statement.mail_subject)
  end
end
