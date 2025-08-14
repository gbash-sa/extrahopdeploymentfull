# Create main project directory
mkdir extrahop-traffic-mirroring
cd extrahop-traffic-mirroring

# Create directory structure
mkdir -p terraform/modules/{cross-account-roles,gwlb,traffic-mirroring}
mkdir -p terraform/environments/{security-account,shared-accounts}
mkdir -p lambda
mkdir -p scripts

# Verify structure
tree .