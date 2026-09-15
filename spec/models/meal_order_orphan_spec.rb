require "rails_helper"

# Issue #315 — une demande de cuisine peut exister AVANT le séjour.
#
# Trois décisions figées par Michael le 2026-09-14 :
#   1. une demande peut exister sans séjour, avec un texte libre qui dit pour qui ;
#   2. elle doit pouvoir être rattachée au séjour une fois celui-ci créé ;
#   3. tant qu'elle est orpheline, elle SORT du facturable.
RSpec.describe MealOrder, "sans séjour" do
  let(:customer) { Customer.create!(email: "orphan@example.com", first_name: "Groupe", last_name: "Tardif") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end

  def orphan(**attrs)
    MealOrder.create!({ kind: "repas", people: 10, date: Date.current + 20,
                        contact_label: "École de Godinne", skip_notifications: true }.merge(attrs))
  end

  describe "validation" do
    it "refuse une demande sans séjour NI texte libre" do
      order = MealOrder.new(kind: "repas", people: 10)

      expect(order).not_to be_valid
      expect(order.errors[:contact_label]).to be_present
    end

    it "accepte une demande avec le seul texte libre" do
      expect(orphan).to be_persisted
    end

    it "accepte une demande avec le seul séjour" do
      order = MealOrder.new(kind: "repas", people: 10, stay: stay, skip_notifications: true)

      expect(order).to be_valid
    end

    it "refuse un texte libre fait d'espaces" do
      order = MealOrder.new(kind: "repas", people: 10, contact_label: "   ")

      expect(order).not_to be_valid
    end
  end

  describe "#client_label" do
    it "prend le nom du client quand il y a un séjour" do
      order = MealOrder.create!(kind: "repas", people: 4, stay: stay, skip_notifications: true)

      expect(order.client_label).to eq("Groupe Tardif")
    end

    it "prend le texte libre quand il n'y en a pas" do
      expect(orphan.client_label).to eq("École de Godinne")
    end

    it "préfère le client du séjour au texte libre une fois rattachée" do
      order = orphan
      order.attach_to_stay!(stay)

      expect(order.client_label).to eq("Groupe Tardif")
    end
  end

  describe "facturable" do
    it "exclut les demandes orphelines du scope billable" do
      order = orphan(status: "requested")

      expect(order).not_to be_billable
      expect(MealOrder.billable).not_to include(order)
    end

    it "les y fait entrer dès le rattachement" do
      order = orphan(status: "requested")
      order.attach_to_stay!(stay)

      expect(order.reload).to be_billable
      expect(MealOrder.billable).to include(order)
    end
  end

  describe "scopes" do
    it "sépare orphan et attached" do
      libre   = orphan
      rattache = MealOrder.create!(kind: "repas", people: 4, stay: stay, skip_notifications: true)

      expect(MealOrder.orphan).to contain_exactly(libre)
      expect(MealOrder.attached).to contain_exactly(rattache)
    end
  end

  describe "#attach_to_stay!" do
    it "conserve le texte libre — c'est la trace du premier contact" do
      order = orphan
      order.attach_to_stay!(stay)

      expect(order.reload.contact_label).to eq("École de Godinne")
      expect(order.stay).to eq(stay)
    end

    it "trace le rattachement dans PaperTrail" do
      order = orphan

      expect { order.attach_to_stay!(stay) }.to change { order.versions.count }.by(1)
      expect(order.versions.last.object_changes).to include("stay_id")
    end

    it "ne déplace jamais une demande déjà rattachée" do
      other = Stay.create!(customer: customer, source: "manual", status: "pending",
                           arrival_date: Date.current + 40, departure_date: Date.current + 41)
      order = MealOrder.create!(kind: "repas", people: 4, stay: stay, skip_notifications: true)

      expect(order.attach_to_stay!(other)).to be(false)
      expect(order.reload.stay).to eq(stay)
    end
  end

  # Le total d'un séjour se lit sur `stay.meal_orders.billable` : une demande
  # rattachée doit l'alimenter sans qu'il faille rouvrir et réenregistrer le séjour.
  it "entre dans le total du séjour dès le rattachement" do
    order = orphan(status: "requested", unit_price_cents: 2_000, people: 5)

    expect(stay.meal_orders.billable.sum(:price_cents)).to eq(0)

    order.attach_to_stay!(stay)

    expect(stay.reload.meal_orders.billable.sum(:price_cents)).to eq(10_000)
  end
end
