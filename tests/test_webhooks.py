"""No real HTTP requests or real lead data in dispatcher tests."""
import concurrent.futures,hashlib,hmac,json,pathlib,socket,ssl,sys,threading,unittest
from unittest.mock import patch,MagicMock
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'vps'))
import webhooks as wh
class WebhookTests(unittest.TestCase):
 def job(self):return dict(id='delivery',claim_token='claim',event_id='event',url='https://example.com/receber',secret='whsec_'+'a'*64,payload={'event_id':'event','consulta':{'nome':'Fictício','cpf':'00000000000'}})
 def dns(self,*ips):return [(socket.AF_INET,socket.SOCK_STREAM,6,'',(ip,443)) for ip in ips]
 def test_signature_uses_original_utf8_body_and_timestamp(self):
  job=self.job();body,sig=wh.signed_body(job['payload'],job['secret'],123)
  self.assertEqual(sig,'v1='+hmac.new(job['secret'].encode(),b'123.'+body,hashlib.sha256).hexdigest());self.assertIn('Fictício'.encode(),body);self.assertEqual(json.loads(body)['event_id'],'event')
  self.assertNotEqual(sig,wh.signed_body(job['payload'],job['secret'],124)[1])
 def test_bad_secret_nan_and_large_payload_rejected(self):
  for secret,payload in [('wrong',{}),(self.job()['secret'],{'a':float('nan')}),(self.job()['secret'],{'a':'x'*262144})]:
   with self.assertRaises(ValueError):wh.signed_body(payload,secret,1)
 def test_destination_rejects_all_private_or_mixed_dns_results(self):
  for ip in ['127.0.0.1','10.0.0.1','169.254.169.254','192.168.0.1','100.64.0.1','::1','fc00::1','fe80::1','::ffff:127.0.0.1']:
   with self.subTest(ip=ip),patch.object(wh.socket,'getaddrinfo',return_value=self.dns('8.8.8.8',ip)),self.assertRaises(wh.DestinationError):wh.destination('https://example.com')
 def test_destination_invalid_schemes_ports_userinfo_and_fragments(self):
  for url in ['http://example.com','https://user:pass@example.com','https://example.com:444','https://example.com/#x','https://example.com/\r\nx','https://[fe80::1%25eth0]/','https://example.com:bad']:
   with self.subTest(url=url),self.assertRaises(wh.DestinationError):wh.destination(url)
 def test_destination_pins_public_address_and_encodes_path(self):
  with patch.object(wh.socket,'getaddrinfo',return_value=self.dns('8.8.8.8')):
   self.assertEqual(wh.destination('https://example.com/ação?a=ç'),('example.com','8.8.8.8','/a%C3%A7%C3%A3o?a=%C3%A7'))
 def test_connect_keeps_original_sni_on_pinned_ip(self):
  conn=wh.PinnedHTTPS('example.com','8.8.8.8');conn._context=MagicMock()
  with patch.object(wh.socket,'create_connection',return_value=MagicMock()) as connect:
   conn.connect();connect.assert_called_once_with(('8.8.8.8',443),timeout=10);self.assertEqual(conn._context.wrap_socket.call_args.kwargs['server_hostname'],'example.com')
 def test_http_outcomes_and_headers_no_redirect_follow(self):
  for status,success,retry in [(200,True,False),(204,True,False),(302,False,False),(400,False,False),(401,False,False),(408,False,True),(425,False,True),(429,False,True),(500,False,True)]:
   with self.subTest(status=status),patch.object(wh,'destination',return_value=('example.com','8.8.8.8','/receber')),patch.object(wh,'PinnedHTTPS') as cls:
    conn=cls.return_value;conn.getresponse.return_value.status=status;r=wh.deliver(self.job())
    self.assertEqual((r['p_success'],r['p_retry']),(success,retry));self.assertEqual(conn.request.call_count,1);headers=conn.request.call_args.kwargs['headers'];self.assertEqual(headers['X-ApoiarCred-Event-Id'],'event');self.assertTrue(headers['X-ApoiarCred-Signature'].startswith('v1='));conn.close.assert_called_once()
 def test_certificate_stop_network_retry_no_error_details(self):
  for exc,retry in [(ssl.SSLCertVerificationError('private secret'),False),(socket.timeout('private secret'),True)]:
   with patch.object(wh,'destination',side_effect=exc):
    r=wh.deliver(self.job());self.assertEqual(r['p_retry'],retry);self.assertNotIn('private secret',r['p_error'])
 def test_invalid_destination_never_connects(self):
  with patch.object(wh,'destination',side_effect=wh.DestinationError),patch.object(wh,'PinnedHTTPS') as cls:
   self.assertFalse(wh.deliver(self.job())['p_retry']);cls.assert_not_called()
 def test_ack_failure_only_retries_database_never_http(self):
  with patch.object(wh,'deliver',return_value=dict(p_success=True,p_http=200,p_error=None,p_retry=False)) as send,patch.object(wh,'rpc',side_effect=[OSError(),True]) as rpc,patch.object(wh.time,'sleep'):
   with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:wh.dispatch_batch([self.job()],pool)
   self.assertEqual(send.call_count,1);self.assertEqual(rpc.call_count,2)
 def test_two_deliveries_run_concurrently(self):
  barrier=threading.Barrier(2)
  def send(job):barrier.wait(timeout=2);return dict(p_success=True,p_http=200,p_error=None,p_retry=False)
  with patch.object(wh,'deliver',side_effect=send),patch.object(wh,'rpc',return_value=True):
   with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:wh.dispatch_batch([self.job(),self.job()],pool)
if __name__=='__main__':unittest.main()
