# Les carnets de l'épicerie (epic #359).
namespace :shop do
  # Idempotente : relancer ne crée aucun doublon et ne retouche aucune règle
  # existante. Elle ne crée que des règles — qui PROPOSENT, un humain accepte.
  desc "Crée les règles d'affectation par mot-clé des carnets (EPICERIE, PAIN, ARTISANAT <PRÉNOM>)"
  task seed_allocation_rules: :environment do
    result = Shop::SeedAllocationRules.new.run

    puts "[shop:seed_allocation_rules] #{result}"
    result.created.each { |rule| puts "  + #{rule.label} → #{rule.general_account}" }
    result.warnings.each { |warning| puts "  ! #{warning}" }
  end
end
