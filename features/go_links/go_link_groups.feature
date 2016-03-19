Feature: golink group sharing correct
 
  I want to see golinks that my groups have access to
  when i remove groups i want the permissions to be correctly updated

Background: golinks have been added to the database

  Given the following golinks exist:
  | key | url | groups |
  | key1 | url1 | g1-key |
  | key2 | url2 | g3-key |
  | key3 | url3 | g1-key,g2-key |
  | key4 | url4 | g1-key-super |

  Given the following groups exist:
  | key | name | creator | emails |
  | g1-key | g1-name | e1@gmail.com | e1@gmail.com | 
  | g2-key | g2-name | e1@gmail.com | e1@gmail.com, e2@gmail.com |
  | g3-key | g3-name | e2@gmail.com | e2@gmail.com |
  | g1-key-super | g4-name | e2@gmail.com | e2@gmail.com |
  | g1 | g5-name | e2@gmail.com | e2@gmail.com |

Scenario: group permissions work on index page
  Given I am logged in as "e1@gmail.com"
  Given I am on the go_menu page
  Then I should see "key1"
  Then I should not see "key2"
  Given I am logged in as "e2@gmail.com"
  Given I am on the go_menu page
  Then I should not see "key1"
  Then I should see "key2"

Scenario: removing a group removes group from golink groups and resets to anyone if none
  Given I am logged in as "e1@gmail.com"
  And I delete the group "g1-key"
  Given I am on the go_menu page
  Then I should not see "g1-key"
  And I should see "Anyone"
  And I should see "g2-key"

Scenario: non creators cannot remove groups
  Given I am logged in as "e2@gmail.com"
  And I delete the group "g1-key"
  Given I am on the go_menu page
  Then I should see "g1-key"

Scenario: group substring superstring permissions working
  Given I am logged in as "e1@gmail.com"
  And I am on the go_menu page
  Then I should not see "key4"
  Given I am logged in as "e2@gmail.com"
  And I am on the go_menu page
  Then I should not see "key1" 

Scenario: should not see groups you are not a part of


