class ConsignmentMailer < ApplicationMailer
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

    mail(to: @consignor.email,
         subject: "Dépôt-vente — vos ventes de #{report.period_label}")
  end
end
