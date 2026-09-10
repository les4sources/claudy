require "rails_helper"

# Présentation d'une ligne de cuisine (epic #219, phase 3).
RSpec.describe MealOrderDecorator do
  let(:customer) { Customer.create!(email: "deco@example.com", first_name: "D", last_name: "Eco") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }

  def decorated(**attrs)
    MealOrder.new({ stay: stay, kind: "repas", people: 4, date: Date.new(2026, 9, 20) }.merge(attrs)).decorate
  end

  it "compose la date et le moment" do
    expect(decorated(moment: "soir").date_label).to include("20 septembre 2026", "Soir")
    expect(decorated(date: nil).date_label).to eq("Sans date")
  end

  it "rend les badges de statut et de validation en français" do
    line = decorated(status: "confirmed", validation: "accepted")
    expect(line.status_badge).to include("Confirmé")
    expect(line.validation_badge).to include("OK")

    expect(decorated(status: "inquiry").status_badge).to include("Info")
    expect(decorated.validation_badge).to include("À valider")
  end

  # Ni coût ni marge par prestation (epic #269) : la rentabilité de la cuisine
  # se lit sur une période, dans la comptabilité.
  it "formate le prix" do
    expect(decorated(price_cents: 6_000).price).to include("60")
  end

  it "tronque les notes et garde le texte complet" do
    long = "a" * 120
    expect(decorated(notes: long).notes_short.length).to be <= 80
    expect(decorated.notes_short).to be_nil
  end

  it "dit qui s'en charge, ou que personne ne s'en charge" do
    steph = Human.create!(name: "Stéphanie", email: "steph@les4sources.be")
    expect(decorated(responsible_human: steph).responsible_label).to eq("Stéphanie")
    expect(decorated).to be_responsible_missing
    expect(decorated.responsible_label).to eq("Personne")
  end

  it "redevient à prendre quand son responsable a quitté le collectif" do
    # `Human` porte un default_scope sur les membres actifs : désactiver
    # quelqu'un laisse `responsible_human_id` rempli et l'association à nil. La
    # ligne doit redevenir proposable, pas rester bloquée sur un fantôme.
    parti = Human.create!(name: "Parti", email: "parti@les4sources.be", status: "active")
    line = decorated(responsible_human: parti)
    expect(line).not_to be_responsible_missing

    parti.update!(status: "inactive")
    expect(decorated(responsible_human_id: parti.id)).to be_responsible_missing
  end

  it "expose le motif qui a sorti la ligne du jeu" do
    expect(decorated(status: "cancelled", cancellation_reason: "Groupe annulé").reason).to eq("Groupe annulé")
    expect(decorated(validation: "refused", refusal_reason: "Pas dispo").reason).to eq("Pas dispo")
    expect(decorated.reason).to be_nil
  end
end
