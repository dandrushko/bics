from keystoneauth1 import session
from keystoneauth1.identity import v3
from keystoneclient.v3 import client as keystone_client
from neutronclient.v2_0 import client as neutron_client

# "BICS-Tenant2"
OS_USERNAME = "admin"
OS_PASSWORD = "VMware1!"
OS_PROJECT_NAME = "BICS-Tenant1"
OS_PROJECT_ID = "5d45ab8c60c44f6f925a284298762cb9"
OS_AUTH_URL = "https://vio-demo.vmw-nfv.wdc:5000/v3/"
OS_PROJECT_DOMAIN_ID="default"
OS_USER_DOMAIN_NAME="default"

# New Tenant Name
NEW_PROJECT = "BICS-Tenant3"


def launch_test():

    auth = v3.Password(username=OS_USERNAME,
                              password=OS_PASSWORD,
                              project_id = OS_PROJECT_ID,
                              project_domain_id=OS_PROJECT_DOMAIN_ID,
                              user_domain_id=OS_USER_DOMAIN_NAME,
                              auth_url=OS_AUTH_URL)
    sess = session.Session(auth=auth)
    resources = get_tenant_resources(sess)

    create_tenant(sess, NEW_PROJECT, resources)


def get_tenant_resources(session):

    neutron = neutron_client.Client(session=session)

    # This map will store tenant resources for recreation
    resources = {}

    # Getting networks map. We need to filter out tenant networks
    nets = neutron.list_networks(project_id=OS_PROJECT_ID)
    resources['networks'] = nets['networks']

    # Getting subnetworks map
    subnets = neutron.list_subnets(project_id=OS_PROJECT_ID)
    resources['subnets'] = subnets['subnets']

    # Getting tenant routers list + router ports
    routers = neutron.list_routers(project_id=OS_PROJECT_ID)
    resources['routers'] = routers['routers']
    # Saving Router ports
    for router in resources['routers']:
        ports = neutron.list_ports(device_id=router['id'])
        resources[router['id']]=ports

    return resources


def create_tenant(sess, new_project, resource_list):

    # Let's check do we already project with this name
    project_exists = False
    keystone = keystone_client.Client(session=sess)
    projects = keystone.projects.list()
    for project in projects:
        if project.name == new_project:
            print "Project " + new_project + " already exists"
            project_exists = True
            break

    # Creating project unless it exists
    if not project_exists:
        keystone.projects.create(name=new_project,
                                 domain=OS_PROJECT_DOMAIN_ID,
                                 description="Automatically created project")
    #################################
    # Authenticating on a new tenant
    auth = v3.Password(username=OS_USERNAME,
                       password=OS_PASSWORD,
                       project_name=new_project,
                       project_domain_id=OS_PROJECT_DOMAIN_ID,
                       user_domain_id=OS_USER_DOMAIN_NAME,
                       auth_url=OS_AUTH_URL)

    new_sess = session.Session(auth=auth)

    # TODO: assign current user role to project and set his role!!!
    """
    keystone = keystone_client.Client(session=new_sess)
    admin_user_object = keystone.users.list(name=OS_USERNAME, domain_id=OS_USER_DOMAIN_NAME)
    print admin_user_object
    roles = keystone.roles.list(project=new_project, domain_id=OS_USER_DOMAIN_NAME)
    admin_role = keystone.roles.get('admin')
    print roles
    print admin_role
    keystone.roles.grant(role=admin_role, user=admin_user_object, project=new_project)
    """

    # Creating networks, then subnets and then routers
    neutron = neutron_client.Client(session=new_sess)
    # This map will store newly created old <-> new net id mapping
    old_network_ids={}
    # Creating networks from source tenant
    for network in resource_list['networks']:
        new_net = neutron.create_network({'network':{
            'name': network['name']}})
        old_network_ids[network['id']] = new_net['network']['id']
        print "Network " + network['name'] + " was created"
    # Creating subnets from the source tenant and attaching them to the newly created networks
    # This map will store newly created old <-> new subnet id mapping
    old_subnet_ids={}
    for subnet in resource_list['subnets']:
         new_subnet = neutron.create_subnet({'subnet': {
            'network_id': old_network_ids[subnet['network_id']],
            'cidr': subnet['cidr'],
            'allocation_pools': subnet['allocation_pools'],
            'dns_nameservers': subnet['dns_nameservers'],
            'enable_dhcp': subnet['enable_dhcp'],
            'gateway_ip': subnet['gateway_ip'],
            'name': subnet['name'],
            'ip_version': subnet['ip_version']}})
         print "Subnet " + subnet['name'] + " was created and attached to network " + \
               old_network_ids[subnet['network_id']]
         old_subnet_ids[subnet['id']] = new_subnet['subnet']['id']

    for router in resource_list['routers']:
        new_router = neutron.create_router({'router':{
            'name': router['name'],
            'admin_state_up': True
        }})
        print "Router " + router['name'] + " was created"
        # Attaching router to subnets
        original_router_id = router['id']
        for port in resource_list[original_router_id]['ports']:
            # We might have either internal or exernal/gw port
            if port['device_owner'] == 'network:router_gateway':
                neutron.add_gateway_router(new_router['router']['id'], {'network_id': port['network_id']})
                print "Router gateway interface was added"

            elif port['device_owner'] == 'network:router_interface':
                # Extracting new subnet id from the mapping and resource_list
                old_port_subnet_id = port['fixed_ips'][0]['subnet_id']
                new_subnet_id = old_subnet_ids[old_port_subnet_id]
                neutron.add_interface_router(new_router['router']['id'], {'subnet_id': new_subnet_id})
                print "Router internal interface was added"

    return

if __name__ == "__main__":
    launch_test()