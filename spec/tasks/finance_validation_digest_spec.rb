require "rails_helper"
require "rake"

# Le CÂBLAGE de la tâche du lundi ; le comportement est couvert par
# `spec/services/purchase_invoices/validation_digest_spec.rb`.
RSpec.describe "finance:validation_digest", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("finance:validation_digest")
  end

  it "tourne et rend compte" do
    task = Rake::Task["finance:validation_digest"]
    task.reenable

    expect { task.invoke }.to output(/\[finance:validation_digest\] aucune facture à valider/).to_stdout
  end
end
