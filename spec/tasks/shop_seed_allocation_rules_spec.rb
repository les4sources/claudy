require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 4 — la tâche sème les règles des carnets, et se relance sans
# rien dupliquer.
RSpec.describe "shop:seed_allocation_rules" do
  include FinanceBuilders

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before do
    Rake::Task["shop:seed_allocation_rules"].reenable
    build_legal_entity(name: "Fondation Les 4 Sources")
    build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue")
    build_general_account(code: "701005", name: "Artisanat", klass: 7, nature: "revenue")
    Consignor.create!(name: "Émilie", settlement_mode: "invoice")
  end

  def run_task
    original_stdout = $stdout
    $stdout = StringIO.new.tap { |io| io.set_encoding(Encoding::UTF_8) }
    Rake::Task["shop:seed_allocation_rules"].reenable
    Rake::Task["shop:seed_allocation_rules"].invoke
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  it "crée les règles, avertit pour le compte manquant, et reste idempotente" do
    output = run_task

    expect(AllocationRule.pluck(:communication_contains)).to contain_exactly("EPICERIE", "ARTISANAT EMILIE")
    expect(output).to include("2 règle(s) créée(s)", "pas de règle « PAIN »")

    expect { run_task }.not_to(change { AllocationRule.count })
  end
end
