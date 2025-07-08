# Migration des Bookings vers Stays

Ce document explique comment migrer les données des anciens **Bookings** vers les nouveaux modèles **Stays** et **Customers**.

## 📋 Contexte

En production, les modèles `Stay` et `Customer` n'existent pas encore. Cette migration permettra de :

1. **Créer des Customers** basés sur les emails des bookings existants
2. **Créer des Stays** avec tous les attributs appropriés
3. **Créer des StayItems** pour les hébergements (lodgings)
4. **Créer des Payments** si des informations de paiement existent
5. **Gérer le rollback** automatique en cas d'erreur

## 🗂️ Mapping des attributs

### Booking → Customer
**Un customer est créé pour chaque booking** :
- Si `email` est présent → Recherche d'un customer existant ou création d'un nouveau
- Si `email` est vide → Création d'un nouveau customer avec email vide
- `firstname` → `customer.firstname`
- `lastname` → `customer.lastname`  
- `phone` → `customer.phone`
- `created_at` et `updated_at` → Préservés

### Booking → Stay
- `user_id` → `1` (utilisateur par défaut pour la migration)
- `id` → `stay.legacy_booking_id` (référence vers l'ancien booking)
- `from_date` → `stay.start_date`
- `to_date` → `stay.end_date`
- `status` → `stay.status`
- `adults` → `stay.adults`
- `children` → `stay.children`
- `babies` → `stay.babies`
- `payment_status` → `stay.payment_status` (calculé après création des payments)
- `notes` → `stay.notes`
- `created_at` et `updated_at` → Préservés
- `invoice_status` → `stay.invoice_status`
- `group_name` → `stay.group_name`
- `estimated_arrival` → `stay.estimated_arrival`
- `departure_time` → `stay.departure_time`
- `comments` → `stay.comments`
- `token` → `stay.token`
- `platform` → `stay.platform`
- `public_notes` → `stay.public_notes`
- `deleted_at` → `stay.deleted_at`
- `price_cents` → `stay.final_price_cents`

### Booking → StayItem
**Logique de priorité** : Si `lodging_id` est présent, seul le lodging est créé (pas de StayItems pour les rooms).

**Pour les hébergements complets (lodgings)** :
Si `lodging_id` est présent :
- Création d'un `StayItem` de type `Lodging`
- `lodging_id` → `stay_item.item_id`
- `from_date` et `to_date` → `stay_item.start_date` et `stay_item.end_date`
- **Les réservations de rooms sont ignorées** (car le lodging complet est réservé)

**Pour les chambres individuelles (rooms)** :
Si le booking a des `reservations` ET `lodging_id` est vide :
- Création d'un `StayItem` de type `Room` pour chaque chambre réservée
- Groupement des réservations par `room_id`
- Les dates utilisées sont celles du booking (pas calculées depuis les réservations individuelles)
- `room_id` → `stay_item.item_id`
- `from_date` et `to_date` du booking → `stay_item.start_date` et `stay_item.end_date`

*Note : Les réservations dans la DB sont des enregistrements individuels pour chaque nuit, mais les StayItems utilisent les dates globales du booking.*

### Booking → Payment
Si `payment_status` et `price_cents` sont présents :
- `price_cents` → `payment.amount_cents`
- `payment_method` → `payment.payment_method` (défaut: 'cash' si vide)
- `payment_status` → `payment.status` (mappé appropriément)

## 🚀 Instructions d'utilisation

### 0. Migration préalable (OBLIGATOIRE)

Avant tout, il faut exécuter la migration Rails pour ajouter la colonne `legacy_booking_id` :

```bash
rails db:migrate
```

Cette migration ajoute la colonne `legacy_booking_id` à la table `stays` avec un index pour les performances.

### 1. Vérification préalable

Avant de lancer la migration, vérifiez l'état actuel :

```bash
rake migration:check_migration_status
```

Cette tâche affiche :
- Le nombre de bookings, stays et customers actuels
- Les bookings avec des données manquantes
- Une estimation du nombre de customers qui seront créés

### 2. Lancement de la migration

```bash
rake migration:migrate_bookings_to_stays
```

⚠️ **IMPORTANT** : Cette tâche doit être lancée dans un environnement où vous pouvez surveiller les logs.

### 3. Vérification post-migration

```bash
rake migration:migration_report
```

Cette tâche affiche un rapport complet sur les données migrées.

## 🔧 Gestion des erreurs

### Rollback automatique

Si une erreur survient pendant la migration :
1. **Tous les stays créés** seront automatiquement supprimés
2. **Tous les nouveaux customers** (sans stays restants) seront supprimés
3. **La transaction sera annulée** complètement
4. **Un message d'erreur détaillé** sera affiché

### Nettoyage manuel (si nécessaire)

⚠️ **DANGER** : Cette tâche supprime TOUTES les données migrées !

```bash
rake migration:clean_migrated_data
```

## 📊 Attributs non migrés

Les attributs suivants des bookings ne sont **pas** migrés :
- `bedsheets`
- `towels`
- `contract_status`
- `option_babysitting`
- `option_partyhall`
- `option_bread`
- `tier`
- `option_discgolf`
- `show_price_cents`
- `option_pizza_party`
- `wifi`

## 🔍 Points d'attention

### Bookings sans email
Les bookings sans email seront migrés avec un customer créé ayant un email vide. Chaque booking aura toujours un customer associé.

### Bookings sans dates
Les bookings sans `from_date` ou `to_date` causeront une erreur et interrompront la migration. Il faut les corriger avant de relancer.

### Tokens en doublon
Si des tokens existent déjà, la migration peut échouer. Dans ce cas, il faudra soit :
- Nettoyer les stays existants
- Modifier la logique de génération de token

### Customers existants
Si un customer avec le même email existe déjà, il sera réutilisé (pas de duplication).

### Référence legacy_booking_id
Chaque stay aura un attribut `legacy_booking_id` qui contient l'ID de l'ancien booking. Cela permet de maintenir une traçabilité entre les anciennes et nouvelles données.

## 📈 Exemple d'utilisation complète

```bash
# 0. Exécuter la migration Rails (OBLIGATOIRE)
rails db:migrate

# 1. Vérifier l'état initial
rake migration:check_migration_status

# 2. Lancer la migration
rake migration:migrate_bookings_to_stays

# 3. Vérifier le résultat
rake migration:migration_report

# 4. Si problème, nettoyer (optionnel)
# rake migration:clean_migrated_data
```

## 🔐 Sécurité

- **Transaction atomique** : Tout ou rien
- **Préservation des timestamps** : Les dates de création/modification originales sont conservées
- **Rollback automatique** : En cas d'erreur, tout est annulé
- **Logs détaillés** : Chaque étape est tracée

---

💡 **Conseil** : Testez d'abord sur un environnement de développement avec une copie des données de production ! 