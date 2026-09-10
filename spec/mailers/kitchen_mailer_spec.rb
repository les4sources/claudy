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

  # Issue #266 — l'email d'une SAISIE : la liste des services, chacun avec ses
  # propres liens de réponse.
  describe "#grouped_request" do
    def grouped(orders) = described_class.grouped_request(orders, steph.email)

    let(:midi) do
      o = MealOrder.new(stay: stay, kind: "repas", moment: "midi", people: 12,
                        date: Date.new(2026, 10, 2), notes: "deux véganes", responsible_human: steph)
      o.skip_notifications = true
      o.tap(&:save!)
    end
    let(:soir) do
      o = MealOrder.new(stay: stay, kind: "repas", moment: "soir", people: 12,
                        date: Date.new(2026, 10, 4), notes: "un sans gluten", responsible_human: steph)
      o.skip_notifications = true
      o.tap(&:save!)
    end
    let(:apero) do
      o = MealOrder.new(stay: stay, kind: "apero", moment: "soir", people: 20,
                        date: Date.new(2026, 10, 3), responsible_human: steph)
      o.skip_notifications = true
      o.tap(&:save!)
    end

    it "nomme le nombre de services, le client et la période dans l'objet" do
      expect(grouped([midi, apero, soir]).subject).to eq("3 services — Groupe Mailer — du 2 au 4/10/2026")
    end

    it "garde les dates entières quand la période change de mois" do
      soir.update_columns(date: Date.new(2026, 11, 3))

      expect(grouped([midi, soir.reload]).subject).to eq("2 services — Groupe Mailer — du 2/10/2026 au 3/11/2026")
    end

    it "préfixe [Info] seulement quand TOUS les services sont des demandes d'info" do
      midi.update_columns(status: "inquiry")
      expect(grouped([midi.reload, soir]).subject).not_to start_with("[Info]")

      soir.update_columns(status: "inquiry")
      expect(grouped([midi.reload, soir.reload]).subject).to start_with("[Info] ")
    end

    it "liste chaque service avec ses précisions et ses convives" do
      body = grouped([midi, apero, soir]).body.encoded

      expect(body).to include("deux véganes", "un sans gluten")
      expect(body).to include("12 pers.", "20 pers.")
      expect(body).to include("Repas (midi ou soir)", "Apéro produits locaux")
    end

    # Chaque ligne porte SON jeton : c'est la ligne qui s'accepte ou se refuse,
    # jamais la saisie entière. Les jetons portent leur date d'expiration, donc
    # ils changent à chaque appel — on compare leur NOMBRE et leur unicité, pas
    # leur valeur.
    it "donne à CHAQUE service sa propre paire de liens de réponse" do
      body = grouped([midi, soir]).body.encoded

      valides = body.scan(%r{/kitchen/validate/([\w\-]+)})
      refus   = body.scan(%r{/kitchen/refuse/([\w\-]+)})
      expect(valides.size).to eq(2)
      expect(refus.size).to eq(2)
      expect(valides.uniq.size).to eq(2)
    end

    it "ne propose pas de réponse sur une ligne déjà tranchée, et garde les autres" do
      midi.update_columns(validation: "accepted")

      body = grouped([midi.reload, soir]).body.encoded

      # Le service accepté reste LISTÉ — il n'attend simplement plus de réponse.
      expect(body.scan(%r{/kitchen/validate/}).size).to eq(1)
      expect(body).to include("deux véganes", "un sans gluten")
    end

    it "n'écrit jamais au client" do
      mail = grouped([midi, soir])

      expect(Array(mail.to) + Array(mail.cc)).not_to include(customer.email)
    end
  end

  it "n'écrit jamais au client, sur aucun des six emails" do
    %i[new_request revalidation_needed changed confirmed cancelled refused].each do |kind|
      mail = described_class.public_send(kind, order, steph.email)
      recipients = Array(mail.to) + Array(mail.cc)
      expect(recipients).not_to include(customer.email), "#{kind} écrit au client"
    end
  end
end
