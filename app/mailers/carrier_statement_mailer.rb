class CarrierStatementMailer < ApplicationMailer
  # Le relevé de rémunération envoyé au porteur d'activité (epic #244, phase 3).
  #
  # HTML et lien à jeton, comme les reversements et les décomptes sourciers :
  # aucune gem PDF au Gemfile, et « Imprimer → Enregistrer en PDF » du navigateur
  # suffit au porteur qui veut archiver son trimestre.
  def statement(statement)
    @statement = statement
    @human = statement.human
    @lines = statement.carrier_statement_lines.chronological

    @statement_url = public_carrier_statement_url(
      statement.token, host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
    )

    mail(to: @human.email, subject: @statement.mail_subject)
  end
end
