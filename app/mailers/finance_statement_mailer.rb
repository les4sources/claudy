class FinanceStatementMailer < ApplicationMailer
  # Décompte mensuel d'un compte sourcier (issue #160).
  #
  # HTML, pas de PDF : aucune gem PDF n'est au Gemfile, et en ajouter une
  # coûterait une dépendance système sur Hatchbox pour un collectif de quinze
  # personnes qui a besoin de LIRE sa note. Le corps porte le détail complet, et
  # le lien à jeton mène à une page imprimable — « Imprimer → Enregistrer en
  # PDF » du navigateur produit le PDF quand la comptable en veut un.
  def statement(statement)
    @statement = statement
    @account = statement.member_account
    @entries = statement.account_entries.chronological
    @statement_url = public_statement_url(statement.token,
                                          host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))

    mail(to: recipient_for(@account), subject: statement.mail_subject)
  end

  # Relance : même page, même montant, ton différent. Action explicite déclenchée
  # par un humain — jamais un job de fond.
  def reminder(statement)
    @statement = statement
    @account = statement.member_account
    @entries = statement.account_entries.chronological
    @statement_url = public_statement_url(statement.token,
                                          host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))

    mail(to: recipient_for(@account), subject: "Rappel — #{statement.mail_subject}")
  end

  private

  # Le compte porte son propre email de contact : il reste joignable même quand
  # la personne a quitté l'équipe et que sa fiche Humain est désactivée.
  def recipient_for(account)
    account.contact_email.presence || account.human&.email
  end
end
