# Emails de la demande de modification de séjour (issue #133).
class StayChangeRequestMailer < ApplicationMailer
  TEAM_EMAIL = "sejours@les4sources.be".freeze

  # Équipe : une nouvelle demande est arrivée, avec son delta.
  def team_new_request(change_request)
    assign(change_request)
    mail(to: TEAM_EMAIL,
         subject: "Demande de modification — séjour ##{@stay.id} (#{@delta_label})")
  end

  # Client : accusé de réception.
  def customer_received(change_request)
    assign(change_request)
    mail(to: @stay.customer.email,
         subject: "Votre demande de modification a bien été reçue")
  end

  # Client : demande approuvée — nouveau total et solde.
  def customer_approved(change_request)
    assign(change_request)
    @stay = change_request.stay.reload
    mail(to: @stay.customer.email,
         subject: "Votre séjour a été modifié")
  end

  # Client : demande refusée — avec le motif.
  def customer_refused(change_request)
    assign(change_request)
    mail(to: @stay.customer.email,
         subject: "Votre demande de modification n'a pas pu être acceptée")
  end

  private

  def assign(change_request)
    @change_request = change_request
    @stay = change_request.stay
    @new_total = format_euros(change_request.new_total_cents)
    @delta_label = signed_euros(change_request.delta_cents)
  end

  def format_euros(cents) = "#{format('%.2f', cents.to_i / 100.0).tr('.', ',')} €"

  def signed_euros(cents)
    "#{cents.to_i.positive? ? '+' : ''}#{format_euros(cents)}"
  end
end
