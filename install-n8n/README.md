ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory.ini install-n8n.yml

# If using vault for passwords
ansible-playbook -i inventory.ini install-n8n.yml --ask-vault-pass