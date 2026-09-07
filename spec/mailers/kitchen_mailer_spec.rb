require "rails_helper"

# Emails INTERNES de la cuisine (epic #219, phase 4).
RSpec.describe KitchenMailer do
  let(:customer) { Customer.create!(email: "client-mailer@example.com", first_name: "Groupe", last_name: "Mailer") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.new(2026, 10, 2), departure_date: Date.new(2026, 10, 4))
  end
  let(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let(:order) do
    o = MealOrder.new(stay: stay, kind: "repas", moment: "soir", people: 12,
                      date: Date.new(2026, 10, 3), notes: "deux véganes", responsible_human: steph)
    o.skip_notifications = true
    o.tap(&:save!)
  end

  it "porte la demande, ses détails et les deux réponses possibles" do
    mail = described_class.new_request(order, steph.email)

    expect(mail.to).to eq(["steph@les4sources.be"])
    expect(mail.subject).to eq("Repas — Groupe Mailer — 3/10/2026")
    body = mail.body.encoded
    expect(body).to include("Groupe Mailer", "12 pers.", "deux véganes")
    expect(body).to include("C&#39;est possible").or include("C'est possible")
    expect(body).to include("/kitchen/validate/", "/kitchen/refuse/")
  end

  it "propose « je m'en charge » pour un buffet, pas une validation" do
    order.update_columns(kind: "buffet_vege")

    body = described_class.new_request(order.reload, steph.email).body.encoded

    expect(body).to include("Je m&#39;en charge").or include("Je m'en charge")
  end

  it "n'offre plus de réponse sur une ligne déjà tranchée" do
    order.update_columns(validation: "accepted")

    body = described_class.new_request(order.reload, steph.email).body.encoded

    expect(body).not_to include("/kitchen/validate/")
  end

  it "annonce le refus à la coordination avec son motif" do
    order.update_columns(validation: "refused", refusal_reason: "Je suis en congé")

    mail = described_class.refused(order.reload, "malau@les4sources.be")

    expect(mail.to).to eq(["malau@les4sources.be"])
    expect(mail.subject).to start_with("Refusé par la cuisine")
    expect(mail.body.encoded).to include("Je suis en congé")
  end

  it "n'écrit jamais au client, sur aucun des six emails" do
    %i[new_request revalidation_needed changed confirmed cancelled refused].each do |kind|
      mail = described_class.public_send(kind, order, steph.email)
      recipients = Array(mail.to) + Array(mail.cc)
      expect(recipients).not_to include(customer.email), "#{kind} écrit au client"
    end
  end
end
