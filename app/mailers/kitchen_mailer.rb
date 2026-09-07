# Emails INTERNES de la cuisine (epic #219, phase 4). Aucun de ces messages ne
# part vers un client : la personne qui cuisine et la coordination, jamais
# d'autre destinataire. C'est pourquoi ils ne sont pas journalisés dans
# `SentEmail`, réservé aux emails clients.
class KitchenMailer < ApplicationMailer
  helper KitchenHelper

  # Nouvelle demande. Pour un repas, deux liens : « C'est possible » et « Pas
  # possible ». Pour un buffet ou un apéro, un seul : « Je m'en charge ».
  def new_request(order, recipient)
    prepare(order, recipient)
    mail(to: recipient, subject: "#{inquiry_prefix}#{demand_label} — #{customer_name} — #{date_label}")
  end

  # La prestation a changé sur une ligne que la cuisine avait acceptée.
  def revalidation_needed(order, recipient)
    prepare(order, recipient)
    mail(to: recipient, subject: "À revalider — #{demand_label} — #{customer_name} — #{date_label}")
  end

  # Même situation, pour un buffet ou un apéro : on informe, on ne redemande rien.
  def changed(order, recipient)
    prepare(order, recipient)
    mail(to: recipient, subject: "Modifié — #{demand_label} — #{customer_name} — #{date_label}")
  end

  def confirmed(order, recipient)
    prepare(order, recipient)
    mail(to: recipient, subject: "Confirmé par le client — #{demand_label} — #{customer_name} — #{date_label}")
  end

  def cancelled(order, recipient)
    prepare(order, recipient)
    mail(to: recipient, subject: "Annulé — #{demand_label} — #{customer_name} — #{date_label}")
  end

  # Refus ou désistement de la cuisine — à la coordination, pour qu'elle
  # reprenne la main auprès du client tout de suite.
  def refused(order, recipient)
    prepare(order, recipient)
    mail(to: recipient, subject: "Refusé par la cuisine — #{demand_label} — #{customer_name} — #{date_label}")
  end

  # Le programme des deux semaines, envoyé le vendredi : Stéphanie fait ses
  # courses le dimanche, c'est ce jour-là qu'elle a besoin de savoir ce qui
  # l'attend. Chacun ne reçoit que SES lignes.
  def weekly_digest(human, orders)
    @human  = human
    @orders = MealOrderDecorator.decorate_collection(orders)
    @days   = @orders.group_by(&:date).sort_by { |date, _| date || Date::Infinity.new }
    @kitchen_url = kitchen_orders_url(host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))
    mail(to: human.email, subject: "Cuisine — les 14 prochains jours")
  end

  # Le pain se commande à la boulangerie, et ça s'oublie. Cinq jours avant.
  def bread_reminder(order, recipient)
    prepare(order, recipient)
    mail(to: recipient, subject: "Pain à commander pour le #{date_label} — #{customer_name}")
  end

  private

  def prepare(order, recipient)
    @order     = order.decorate
    @recipient = recipient
    @stay      = order.stay
    @link_host = ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
    @token     = order.validation_token
    @kitchen_url = kitchen_orders_url(host: @link_host)
  end

  def demand_label = @order.family_label

  def customer_name = @stay&.customer&.name.presence || "Séjour"

  def date_label = @order.date.present? ? l(@order.date, format: "%-d/%m/%Y") : "date à fixer"

  def inquiry_prefix = @order.inquiry? ? "[Info] " : ""
end
