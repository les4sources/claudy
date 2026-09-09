require "rails_helper"

# Issue #266 — une saisie, un email par destinataire. La règle qui prime sur
# tout reste la même : aucun email ne part jamais vers le client.
RSpec.describe Kitchen::GroupedNotifier do
  let(:customer) { Customer.create!(email: "client-groupe@example.com", first_name: "Groupe", last_name: "Dupont") }
  let(:lundi) { Date.current.next_occurring(:monday) + 14 }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: lundi, departure_date: lundi + 4)
  end
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:michael) { Human.create!(name: "Michael", email: "michael@les4sources.be", status: "active") }

  before { ActionMailer::Base.deliveries.clear }

  def build_order(**attrs)
    order = stay.meal_orders.new({ kind: "repas", moment: "midi", people: 8, date: lundi,
                                   status: "requested", responsible_human: steph }.merge(attrs))
    order.skip_notifications = true
    order.tap(&:save!)
  end

  def deliveries = ActionMailer::Base.deliveries

  it "envoie UN seul email pour six lignes destinées à la même personne" do
    orders = (0..5).map { |i| build_order(date: lundi + (i / 2), moment: i.even? ? "midi" : "soir") }

    described_class.new(orders: orders).call

    expect(deliveries.size).to eq(1)
    expect(deliveries.last.to).to eq(["steph@les4sources.be"])
    expect(deliveries.last.subject).to start_with("6 services — Groupe Dupont —")
  end

  it "envoie un email à chacun quand la saisie vise deux destinataires" do
    repas = (0..3).map { |i| build_order(date: lundi + i) }
    buffets = (0..1).map { |i| build_order(kind: "buffet_vege", date: lundi + i, responsible_human: michael) }

    described_class.new(orders: repas + buffets).call

    expect(deliveries.size).to eq(2)
    expect(deliveries.map { |m| m.to.first }).to match_array(%w[steph@les4sources.be michael@les4sources.be])

    chez_michael = deliveries.find { |m| m.to == ["michael@les4sources.be"] }
    expect(chez_michael.subject).to start_with("2 services")
    expect(chez_michael.body.encoded).to include("Buffet végétarien")
    expect(chez_michael.body.encoded).not_to include("Repas (midi ou soir)")
  end

  it "retombe sur l'email individuel quand une seule ligne concerne la personne" do
    described_class.new(orders: [build_order]).call

    expect(deliveries.size).to eq(1)
    expect(deliveries.last.subject).to eq("Repas — Groupe Dupont — #{I18n.l(lundi, format: '%-d/%m/%Y')}")
  end

  it "range chaque ligne chez son propre destinataire, jamais chez l'autre" do
    described_class.new(orders: [build_order,
                                 build_order(kind: "apero", moment: "soir", responsible_human: michael)]).call

    expect(deliveries.map { |m| m.to.first }).to match_array(%w[steph@les4sources.be michael@les4sources.be])
    expect(deliveries.size).to eq(2)
  end

  it "n'envoie rien, sans planter, quand personne n'est joignable" do
    orders = [build_order(kind: "apero", responsible_human: nil),
              build_order(kind: "apero", moment: "soir", responsible_human: nil)]

    expect { described_class.new(orders: orders).call }.not_to change { deliveries.size }
  end

  it "n'écrit jamais au client" do
    described_class.new(orders: [build_order, build_order(moment: "soir")]).call

    recipients = deliveries.flat_map { |m| Array(m.to) + Array(m.cc) }
    expect(recipients).not_to include(customer.email)
  end

  it "ne fait rien du tout sans aucune ligne" do
    expect { described_class.new(orders: []).call }.not_to change { deliveries.size }
  end
end
