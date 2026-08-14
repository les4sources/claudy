require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# Les trois filets du lot B. Une comptabilité qui se contredit toute seule ne
# vaut que si quelqu'un l'écoute — ces tâches sont cette écoute.
RSpec.describe "accounting rakes" do
  include FinanceBuilders

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { %w[seed_reference verify_double_entry verify_numbering verify_internal_transfers].each { |t| Rake::Task["accounting:#{t}"].reenable } }

  def run_task(name)
    Rake::Task["accounting:#{name}"].invoke
    :ok
  rescue SystemExit
    :exit_1
  end

  describe "seed_reference" do
    it "pose le référentiel et ne le repose pas deux fois" do
      expect { run_task("seed_reference") }.to change { GeneralAccount.count }.from(0)

      Rake::Task["accounting:seed_reference"].reenable
      expect { run_task("seed_reference") }.not_to change { GeneralAccount.count }
    end
  end

  describe "verify_double_entry" do
    let(:entity) { build_legal_entity }
    let!(:fiscal_year) { build_fiscal_year(entity) }
    let(:bank) { build_general_account(code: "550000", name: "Banque") }
    let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }

    it "sort sans écart sur des écritures équilibrées" do
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)

      expect { expect(run_task("verify_double_entry")).to eq(:ok) }.to output(/Aucun écart/).to_stdout
    end

    # Le déséquilibre est impossible par le modèle : on force en base pour
    # vérifier que le filet attrape ce que le modèle n'a pas vu passer.
    it "attrape un déséquilibre forcé en base" do
      entry = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)
      entry.journal_lines.first.update_column(:debit_cents, 999)

      expect { expect(run_task("verify_double_entry")).to eq(:exit_1) }.to output(/déséquilibre/i).to_stdout
    end
  end

  describe "verify_numbering" do
    let(:entity) { build_legal_entity }
    let!(:fiscal_year) { build_fiscal_year(entity) }
    let(:bank) { build_general_account(code: "550000", name: "Banque") }
    let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }

    it "sort sans écart sur une séquence continue" do
      2.times { post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue) }

      expect { expect(run_task("verify_numbering")).to eq(:ok) }.to output(/Aucun écart/).to_stdout
    end

    it "signale un numéro manquant" do
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)
      entry = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)
      entry.update_column(:number, 5)

      expect { expect(run_task("verify_numbering")).to eq(:exit_1) }.to output(/manquant/i).to_stdout
    end
  end

  describe "verify_internal_transfers" do
    let(:entity) { build_legal_entity }
    let!(:fiscal_year) { build_fiscal_year(entity) }
    let!(:transfers) do
      build_general_account(code: GeneralAccount::INTERNAL_TRANSFER_CODE, name: "Virements internes")
    end
    let(:bank) { build_general_account(code: "550000", name: "Banque") }

    it "sort sans écart quand les virements se soldent" do
      post_simple_entry(entity: entity, debit_account: transfers, credit_account: bank)
      post_simple_entry(entity: entity, debit_account: bank, credit_account: transfers)

      expect { expect(run_task("verify_internal_transfers")).to eq(:ok) }.to output(/Aucun écart/).to_stdout
    end

    it "signale un virement interne qui ne se referme pas" do
      post_simple_entry(entity: entity, debit_account: transfers, credit_account: bank)

      expect { expect(run_task("verify_internal_transfers")).to eq(:exit_1) }.to output(/virements internes/i).to_stdout
    end
  end
end
