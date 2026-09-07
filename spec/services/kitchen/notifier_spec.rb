require "rails_helper"

# Qui est prévenu, de quoi (epic #219, phase 4). La règle qui prime sur tout :
# aucun email ne part jamais vers le client.
RSpec.describe Kitchen::Notifier do
  let(:customer) { Customer.create!(email: "client@example.com", first_name: "Client", last_name: "Test") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:michael) { Human.create!(name: "Michael", email: "michael@les4sources.be", status: "active") }

  before { ActionMailer::Base.deliveries.clear }

  def last_mail = ActionMailer::Base.deliveries.last

  def create_order(**attrs)
    stay.meal_orders.create!({ kind: "repas", people: 10, date: Date.current + 20,
                               responsible_human: steph }.merge(attrs))
  end

  it "prévient le responsable à la création" do
    order = create_order

    expect(last_mail.to).to eq(["steph@les4sources.be"])
    expect(last_mail.subject).to include("Repas", "Client Test")
    expect(order.reload).to be_pending
  end

  it "marque une demande d'info dans l'objet" do
    create_order(status: "inquiry")

    expect(last_mail.subject).to start_with("[Info]")
  end

  it "retombe sur le responsable par défaut de la famille" do
    Setting.set("kitchen.buffet.default_human_id", michael.id)

    create_order(kind: "buffet_vege", responsible_human: nil)

    expect(last_mail.to).to eq(["michael@les4sources.be"])
  end

  it "n'envoie rien, sans planter, quand personne n'est joignable" do
    expect { create_order(kind: "apero", responsible_human: nil) }
      .not_to change { ActionMailer::Base.deliveries.size }
  end

  it "demande une revalidation quand un repas accepté change" do
    order = create_order
    order.accept!
    ActionMailer::Base.deliveries.clear

    order.update!(people: 20)

    expect(last_mail.subject).to start_with("À revalider")
    expect(last_mail.to).to eq(["steph@les4sources.be"])
  end

  it "informe seulement, pour un buffet dont quelqu'un se charge déjà" do
    order = create_order(kind: "buffet_vege", responsible_human: michael)
    order.accept!
    ActionMailer::Base.deliveries.clear

    order.update!(date: Date.current + 25)

    expect(last_mail.subject).to start_with("Modifié")
  end

  it "ne dit rien quand seules les notes changent" do
    order = create_order
    order.accept!
    ActionMailer::Base.deliveries.clear

    order.update!(notes: "sans gluten")

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "annonce la confirmation du client, puis l'annulation" do
    order = create_order
    ActionMailer::Base.deliveries.clear

    order.update!(status: "confirmed")
    expect(last_mail.subject).to start_with("Confirmé par le client")

    order.update!(status: "cancelled", cancellation_reason: "Groupe annulé")
    expect(last_mail.subject).to start_with("Annulé")
    expect(last_mail.body.encoded).to include("Groupe annulé")
  end

  it "prévient la coordination — et elle seule — d'un refus" do
    order = create_order
    ActionMailer::Base.deliveries.clear

    order.refuse!("Je suis en congé")

    expect(last_mail.to).to eq([Kitchen::Config.coordinator_email])
    expect(last_mail.subject).to start_with("Refusé par la cuisine")
    expect(last_mail.body.encoded).to include("Je suis en congé")
  end

  it "ne relance plus rien sur une ligne annulée" do
    order = create_order(status: "cancelled", cancellation_reason: "annulé d'emblée")
    ActionMailer::Base.deliveries.clear

    order.update!(people: 30)

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "n'écrit jamais au client" do
    order = create_order
    order.update!(status: "confirmed")
    order.refuse!("indisponible")

    recipients = ActionMailer::Base.deliveries.flat_map { |m| Array(m.to) }
    expect(recipients).not_to include(customer.email)
  end

  it "se tait quand skip_notifications est posé" do
    order = MealOrder.new(stay: stay, kind: "repas", people: 8, date: Date.current + 10,
                          responsible_human: steph)
    order.skip_notifications = true

    expect { order.save! }.not_to change { ActionMailer::Base.deliveries.size }
  end
end
