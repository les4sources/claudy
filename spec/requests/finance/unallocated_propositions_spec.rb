require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require Rails.root.join("spec/support/mail_intake_helpers")

# « Proposer pour toutes les lignes affichées » (Michael, 2026-11-26) : Jev sur
# toute la page de la file d'un coup, puis une revue où l'on valide, refuse, ou
# accepte un lot borné par son compte.
RSpec.describe "Finances > À affecter > proposer pour toutes les lignes", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:bar) { build_general_account(code: "701001", name: "Bar", klass: 7, nature: "revenue") }
  let!(:epicerie) { build_general_account(code: "704000", name: "Épicerie", klass: 7, nature: "revenue") }
  let!(:cash_account) { build_cash_account(entity, bank_account) }

  def ligne(montant, nom, communication)
    build_cash_entry(cash_account, amount_cents: montant, label: "Payconiq").tap do |e|
      e.update!(counterparty_name: nom, communication: communication)
    end
  end

  let!(:biere) { ligne(450, "DUPONT MARIE", "consos bar") }
  let!(:soft) { ligne(320, "MARTIN PAUL", "bar soft") }
  let!(:pain) { ligne(780, "LEROY ANNE", "pain epicerie") }

  # Jev répond « Bar » à tout ce qui parle de bar, « Épicerie » au reste.
  let(:jev) do
    Class.new(MailIntakeHelpers::FakeJev) do
      def ask(state:, questions:)
        @calls << { state: state, questions: questions }
        compte = state["ligne"]["communication"].include?("bar") ? "701001 Bar" : "704000 Épicerie"
        { "compte" => { "choice" => compte, "confidence" => 0.93 } }
      end
    end.new
  end

  before do
    sign_in user
    Finance::AllocationHistory.reset!
    [[350, "consos bar", bar], [900, "pain epicerie", epicerie]].each_with_index do |(montant, texte, compte), i|
      precedent = build_cash_entry(cash_account, amount_cents: montant, entry_date: Date.new(2026, 5, 2 + i), label: "Payconiq")
      precedent.update!(counterparty_name: "ANCIEN", communication: texte)
      allocate(precedent, account: compte, amount_cents: montant, entity: entity)
      Accounting::PostCashEntry.new(cash_entry: precedent).run!
    end
    allow(Jev::Client).to receive(:new).and_return(jev)
  end

  it "montre le bouton sur la file, avec les filtres de la page" do
    allow(Jev::Client).to receive(:api_key).and_return("cle-de-test")

    get finance_unallocated_cash_entries_path(q: "bar")

    expect(response.body).to include("Proposer pour toutes les lignes affichées")
    expect(response.body).to include(%(action="#{finance_unallocated_propositions_path}"))
    expect(response.body).to include(%(name="q" value="bar"))
  end

  it "demande Jev pour chaque ligne affichée, sans rien affecter, puis ouvre la revue" do
    expect do
      post finance_unallocated_propositions_path
    end.not_to(change { CashAllocation.count })

    expect(response).to redirect_to(finance_unallocated_propositions_path)
    expect(jev.calls.size).to eq(3)
    expect([biere, soft, pain].map { |e| e.reload.allocation_suggestions.pending.count }).to all(eq(1))
    expect([biere, soft, pain].map { |e| e.reload.jev_checked_at }).to all(be_present)
  end

  it "respecte les filtres de la file" do
    post finance_unallocated_propositions_path(q: "bar")

    expect(response).to redirect_to(finance_unallocated_propositions_path(q: "bar"))
    expect(jev.calls.size).to eq(2)
    expect(pain.reload.allocation_suggestions).to be_empty
  end

  it "range les propositions par lot, le plus gros d'abord, chaque ligne cochée" do
    post finance_unallocated_propositions_path
    get finance_unallocated_propositions_path

    expect(response).to have_http_status(:ok)
    corps = response.body
    expect(corps.index("701001 Bar")).to be < corps.index("704000 Épicerie")
    expect(corps).to include("Accepter les 2 lignes cochées")
    expect(corps).to include(%(name="revue[page]" value="1"))
    suggestion = biere.reload.allocation_suggestions.pending.first
    expect(corps).to match(/name="ids\[\]"[^>]*value="#{suggestion.id}"[^>]*checked|checked[^>]*name="ids\[\]"[^>]*value="#{suggestion.id}"/)
  end

  it "accepte un lot de Jev, seulement les lignes cochées" do
    post finance_unallocated_propositions_path
    cochee = biere.reload.allocation_suggestions.pending.first

    post bulk_finance_allocation_suggestions_path,
         params: { jev_account_id: bar.id, confidence: 93, ids: [cochee.id], revue: { q: "", page: "1" } }

    expect(response).to redirect_to(finance_unallocated_propositions_path(page: "1"))
    expect(flash[:notice]).to include("1 ligne(s) acceptée(s) pour Jev → 701001 Bar")
    expect(biere.reload.cash_allocations.sum(:amount_cents)).to eq(450)
    expect(soft.reload.cash_allocations).to be_empty
    expect(soft.allocation_suggestions.pending.count).to eq(1)
  end

  it "n'accepte rien d'un compte Jev sans cases cochées" do
    post finance_unallocated_propositions_path

    post bulk_finance_allocation_suggestions_path, params: { jev_account_id: bar.id, confidence: 93, revue: { page: "1" } }

    expect(response).to redirect_to(finance_unallocated_propositions_path(page: "1"))
    expect(flash[:alert]).to eq("Coche au moins une ligne du lot.")
    expect(CashAllocation.where(cash_entry: [biere, soft]).count).to eq(0)
  end

  it "ignore une case d'un autre lot glissée dans le formulaire" do
    post finance_unallocated_propositions_path
    intruse = pain.reload.allocation_suggestions.pending.first

    post bulk_finance_allocation_suggestions_path,
         params: { jev_account_id: bar.id, confidence: 93, ids: [intruse.id], revue: { page: "1" } }

    expect(pain.reload.cash_allocations).to be_empty
  end

  it "refuse une ligne depuis la revue sans recharger : elle sort de la page" do
    post finance_unallocated_propositions_path
    suggestion = soft.reload.allocation_suggestions.pending.first

    patch finance_allocation_suggestion_path(suggestion, decision: "reject"),
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Referer" => "http://www.example.com#{finance_unallocated_propositions_path}" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="remove" target="proposition-#{suggestion.id}"))
    expect(suggestion.reload.status).to eq("rejected")
  end

  it "liste les lignes sans proposition, avec la raison" do
    allow(Jev::Client).to receive(:new).and_return(
      MailIntakeHelpers::FakeJev.new { |_id, _q| { "choice" => bar.to_s, "confidence" => 0.4 } }
    )

    post finance_unallocated_propositions_path
    get finance_unallocated_propositions_path

    expect(response.body).to include("Sans proposition (3)")
    expect(response.body).to include("Jev n&#39;est pas assez sûr")
  end

  it "dit quand Jev n'est pas configuré" do
    allow(Jev::Client).to receive(:new).and_call_original
    allow(Jev::Client).to receive(:api_key).and_return(nil)

    post finance_unallocated_propositions_path

    expect(flash[:alert]).to include("Jev n'est pas configuré")
  end
end
