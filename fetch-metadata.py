import urllib2
import sys

def getMetadata(url):
        try:
                req = urllib2.Request(url, None, {'Metadata-Flavor': 'Google'})
                res =  urllib2.urlopen(req)
        except urllib2.HTTPError, e:
                #print(e.code)
                #print(e.read)
                return ''
        except urllib2.URLError, e:
                if hasattr(e, 'reason'):
                #        print('We failed to reach a server.')
                #        print('Reason: ', e.reason)
                        return ''
                elif hasattr(e, 'code'):
                #        print('The server couldn\'t fulfill the request.')
                #        print('Error code: ', e.code)
                        return ''
                else:
                        return ''
        data =  res.read()
        list = data.split('/')
        idx = len(list)-1
        return list[idx]

def main():

        if len(sys.argv) != 2:
                print ''
                return

        argname = sys.argv[1]

        baseurl = 'http://metadata.google.internal/computeMetadata/v1/'
        if argname == 'zone':
                url = baseurl + '/instance/zone'
        elif argname == 'project-id':
                url = baseurl + '/project/project-id'
        elif argname == 'numberOfWorkers':
                url = baseurl+'/instance/attributes/numberOfWorkers'
        elif argname == 'clusterMachineType':
                url = baseurl+'/instance/attributes/clusterMachineType'
        elif argname == 'glusterDiskSize':
                url = baseurl+'/instance/attributes/glusterDiskSize'
	elif argname == 'clusterMachineImage':
		url = baseurl+'/instance/attributes/clusterMachineImage'
        else:
                print ''
                return
        data = getMetadata(url)
        print  data

if __name__ == '__main__':
        main()
