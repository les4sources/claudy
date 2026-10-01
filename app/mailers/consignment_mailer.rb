class ConsignmentMailer < ApplicationMailer
  # La compta reçoit chaque demande en copie cachée : c'est elle qui vérifie et
  # règle les relevés, elle doit savoir qui a été sollicité et quand.
  ACCOUNTING_EMAIL = "compta@les4sources.be".freeze

  # La demande mensuelle de déclaration (epic #248, phase 2).
  #
  # Un lien, un mois, rien d'autre. L'artisan ouvre sur son téléphone, tape ses
  # ventes et valide : c'est tout ce qu'on attend de lui.
  # `monthly_request` et pas `request` : `request` est déjà la requête HTTP dans
  # ActionMailer, et la redéfinir casse le mailer sans message clair.
  def monthly_request(report)
    @report = report
    @consignor = report.consignor
    @report_url = public_consignment_report_url(
      report.token, host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
    )

    # On garde le bcc d'archivage par défaut et on y ajoute la compta.
    mail(to: @consignor.email,
         bcc: [ENV["DEFAULT_BCC_EMAIL"], ACCOUNTING_EMAIL].compact_blank,
         subject: "Dépôt-vente — vos ventes de #{report.period_label}")
  end
end
