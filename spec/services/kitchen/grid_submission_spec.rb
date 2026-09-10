require "rails_helper"

# Issue #265 — une seule saisie pour toutes les prestations d'un séjour.
# Le séjour est la seule chose partagée ; chaque bloc porte son type, ses
# convives et son statut client, et la transaction est unique.
RSpec.describe Kitchen::GridSubmission do
  let(:lundi) { Date.current.next_occurring(:monday) + 14 }
  let(:stay) do
    Stay.create!(customer: Customer.create!(first_name: "Groupe", last_name: "Blocs",
                                            email: "blocs@example.com"),
                 status: "pending", arrival_date: lundi, departure_date: lundi + 3)
  end

  def block(index:, cells: {}, **attributes)
    described_class::Block.new(index: index, cells: cells,
                               attributes: { people: 6, status: "requested" }.merge(attributes))
  end

  def run(*blocks)
    described_class.new(stay: stay, blocks: blocks).run
  end

  it "crée les lignes de chaque bloc avec SON type, SES convives et SON statut" do
    result = run(
      block(index: 0, kind: "apero", people: 12, status: "requested",
            cells: { lundi.iso8601 => { "soir" => "1" } }),
      block(index: 1, kind: "buffet_vege", people: 30, status: "inquiry",
            cells: { (lundi + 1).iso8601 => { "midi" => "1", "soir" => "1" } })
    )

    expect(result).to be_success
    expect(result.orders.size).to eq(3)

    apero = stay.meal_orders.where(kind: "apero").sole
    expect(apero.people).to eq(12)
    expect(apero.status).to eq("requested")

    buffets = stay.meal_orders.where(kind: "buffet_vege")
    expect(buffets.count).to eq(2)
    expect(buffets.pluck(:people).uniq).to eq([30])
    expect(buffets.pluck(:status).uniq).to eq(["inquiry"])
  end

  it "nomme le bloc fautif et ne crée RIEN quand l'un d'eux est vide" do
    expect {
      result = run(
        block(index: 0, kind: "repas", cells: { lundi.iso8601 => { "midi" => "1" } }),
        block(index: 1, kind: "apero", cells: {})
      )
      expect(result).not_to be_success
      expect(result.error).to eq("Prestation 2 : coche au moins un service à préparer.")
    }.not_to change(MealOrder, :count)
  end

  it "annule la saisie entière dès qu'une ligne est invalide" do
    expect {
      result = run(
        block(index: 0, kind: "repas", cells: { lundi.iso8601 => { "midi" => "1", "soir" => "1" } }),
        block(index: 1, kind: "n_importe_quoi", cells: { lundi.iso8601 => { "midi" => "1" } })
      )
      expect(result).not_to be_success
      expect(result.error).to start_with("Prestation 2 :")
    }.not_to change(MealOrder, :count)
  end

  it "retombe sur date + moment uniques pour un bloc sans grille" do
    result = run(block(index: 0, kind: "apero", date: lundi.iso8601, moment: "soir"))

    expect(result).to be_success
    ligne = result.orders.sole
    expect(ligne.date).to eq(lundi)
    expect(ligne.moment).to eq("soir")
  end

  it "refuse une saisie sans séjour" do
    result = described_class.new(stay: nil, blocks: [block(index: 0, kind: "repas")]).run

    expect(result.error).to eq("Choisis d'abord un séjour.")
  end

  it "refuse une saisie sans aucune prestation" do
    expect(run.error).to eq("Ajoute au moins une prestation.")
  end

  it "n'invente un goûter que dans un bloc de la famille repas" do
    run(
      block(index: 0, kind: "repas",
            cells: { lundi.iso8601 => { "midi" => "1", "gouter" => "1" } }),
      block(index: 1, kind: "buffet_viande",
            cells: { (lundi + 1).iso8601 => { "midi" => "1", "gouter" => "1" } })
    )

    expect(stay.meal_orders.where(kind: "gouter").count).to eq(1)
    expect(stay.meal_orders.where(kind: "buffet_viande").count).to eq(2)
  end

  # Issue #266 — la saisie prévient elle-même la cuisine, une fois commitée :
  # un seul email par destinataire, jamais un par ligne.
  describe "les emails de la saisie" do
    let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
    let!(:michael) { Human.create!(name: "Michael", email: "michael@les4sources.be", status: "active") }

    before { ActionMailer::Base.deliveries.clear }

    def deliveries = ActionMailer::Base.deliveries

    it "n'envoie qu'UN email pour les six services d'une même personne" do
      result = run(block(index: 0, kind: "repas", responsible_human_id: steph.id,
                         cells: { lundi.iso8601 => { "midi" => "1", "soir" => "1" },
                                  (lundi + 1).iso8601 => { "midi" => "1", "soir" => "1" },
                                  (lundi + 2).iso8601 => { "midi" => "1", "soir" => "1" } }))

      expect(result.orders.size).to eq(6)
      expect(deliveries.size).to eq(1)
      expect(deliveries.last.to).to eq(["steph@les4sources.be"])
      expect(deliveries.last.subject).to start_with("6 services — Groupe Blocs —")
    end

    it "envoie un email à chacun quand les blocs visent deux personnes" do
      run(
        block(index: 0, kind: "repas", responsible_human_id: steph.id,
              cells: { lundi.iso8601 => { "midi" => "1", "soir" => "1" } }),
        block(index: 1, kind: "buffet_vege", responsible_human_id: michael.id,
              cells: { (lundi + 1).iso8601 => { "midi" => "1", "soir" => "1" } })
      )

      expect(deliveries.size).to eq(2)
      expect(deliveries.map { |m| m.to.first })
        .to match_array(%w[steph@les4sources.be michael@les4sources.be])

      chez_steph = deliveries.find { |m| m.to == ["steph@les4sources.be"] }
      expect(chez_steph.body.encoded).not_to include("Buffet végétarien")
    end

    it "repart sur l'email individuel quand la saisie ne crée qu'une ligne" do
      run(block(index: 0, kind: "apero", responsible_human_id: michael.id,
                cells: { lundi.iso8601 => { "soir" => "1" } }))

      expect(deliveries.size).to eq(1)
      expect(deliveries.last.subject).to start_with("Apéro — Groupe Blocs —")
    end

    it "n'envoie RIEN quand la saisie échoue" do
      expect {
        run(
          block(index: 0, kind: "repas", responsible_human_id: steph.id,
                cells: { lundi.iso8601 => { "midi" => "1" } }),
          block(index: 1, kind: "n_importe_quoi", responsible_human_id: steph.id,
                cells: { lundi.iso8601 => { "soir" => "1" } })
        )
      }.not_to change { deliveries.size }
    end

    it "n'écrit jamais au client" do
      run(block(index: 0, kind: "repas", responsible_human_id: steph.id,
                cells: { lundi.iso8601 => { "midi" => "1", "soir" => "1" } }))

      recipients = deliveries.flat_map { |m| Array(m.to) + Array(m.cc) }
      expect(recipients).not_to include(stay.customer.email)
    end

    # Le prix affiché doit être celui d'APRÈS la remise : elle se pose en
    # `after_commit`, donc après que la saisie a construit ses objets.
    it "annonce le prix de formule quand la journée forme un trio" do
      run(block(index: 0, kind: "repas", people: 10, responsible_human_id: steph.id,
                cells: { lundi.iso8601 => { "midi" => "1", "gouter" => "1", "soir" => "1" } }))

      total = stay.meal_orders.of_family("repas").where(date: lundi).sum(:price_cents)
      expect(total).to eq(Pricing::Catalog.meal_per_person_cents("trio") * 10)
      expect(deliveries.last.body.encoded).to include(ActionController::Base.helpers.strip_tags(
        MealOrder.where(kind: "gouter").sole.decorate.price
      ))
    end
  end

  # La remise trio est recalculée en `after_commit` : elle voit donc l'état
  # APRÈS la transaction, toutes lignes confondues. C'est ce qui la rend juste
  # quand la journée est garnie par plusieurs blocs à la fois.
  it "forme la remise trio sur les repas du jour et laisse l'apéro au tarif plein" do
    run(
      block(index: 0, kind: "repas", people: 10,
            cells: { lundi.iso8601 => { "midi" => "1", "gouter" => "1", "soir" => "1" } }),
      block(index: 1, kind: "apero", people: 10,
            cells: { lundi.iso8601 => { "soir" => "1" } })
    )

    repas = stay.meal_orders.of_family("repas").where(date: lundi)
    expect(repas.sum(:price_cents)).to eq(Pricing::Catalog.meal_per_person_cents("trio") * 10)

    apero = stay.meal_orders.where(kind: "apero").sole
    expect(apero.price_cents).to eq(Pricing::Catalog.meal_per_person_cents("apero") * 10)
  end
end
