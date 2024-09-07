# Configuración del servicio kube-apiserver

-----------------------------------------------

Este archivo define el servicio kube-apiserver y cómo se comunica con etcd usando TLS.

Archivo: `/etc/systemd/system/kube-apiserver.service`

```bash 
[Unit]
Description=Kubernetes API Server
Documentation=https://kubernetes.io/docs/concepts/overview/components/
After=network.target

[Service]
ExecStart=/opt/bin/kube-apiserver \
  --advertise-address=10.17.4.21 \
  --allow-privileged=true \
  --authorization-mode=Node,RBAC \
  --client-ca-file=/etc/kubernetes/pki/ca.crt \
  --enable-admission-plugins=NodeRestriction \
  --etcd-servers=https://127.0.0.1:2379 \
  --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt \
  --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt \
  --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key \
  --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt \
  --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key \
  --runtime-config=api/all=true \
  --service-account-key-file=/etc/kubernetes/pki/sa.pub \
  --service-account-signing-key-file=/etc/kubernetes/pki/sa.key \
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \
  --service-cluster-ip-range=10.96.0.0/12 \
  --tls-cert-file=/etc/kubernetes/pki/apiserver.crt \
  --tls-private-key-file=/etc/kubernetes/pki/apiserver.key \
  --v=2
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## 5. Certificados para kube-apiserver

Eliminar certificados anteriores:
    
```bash
sudo rm /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.csr
```

**Generar nueva clave privada:**

```bash
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/apiserver.key -pkeyopt rsa_keygen_bits:2048
```

**Crear la solicitud de firma de certificado (CSR):**

```bash
sudo openssl req -new -key /etc/kubernetes/pki/apiserver.key -out /etc/kubernetes/pki/apiserver.csr -subj "/CN=kube-apiserver"
```

**Crear archivo de configuración de OpenSSL:**
    
```bash
sudo vim /etc/kubernetes/pki/v3_req.cnf
```

**Contenido del archivo de configuración:**


```bash
[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = 10.17.4.22
IP.2 = 10.96.0.1
```

**Firmar el CSR para generar el certificado:**

```bash
sudo openssl x509 -req -in /etc/kubernetes/pki/apiserver.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /etc/kubernetes/pki/apiserver.crt -days 365 -extensions v3_req -extfile /etc/kubernetes/pki/v3_req.cnf
```

## 6. Certificado de cliente para etcd

**Eliminar los certificados y claves anteriores:**
    
```bash
sudo rm /etc/kubernetes/pki/apiserver-etcd-client.key /etc/kubernetes/pki/apiserver-etcd-client.crt /etc/kubernetes/pki/apiserver-etcd-client.csr
```

**Generar nueva clave privada para apiserver-etcd-client:**

```bash
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
```

**Crear la CSR para el cliente apiserver-etcd-client:**

```bash
sudo openssl req -new -key /etc/kubernetes/pki/apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client" -out /etc/kubernetes/pki/apiserver-etcd-client.csr
```

**Firmar el CSR con la CA de etcd:**

```bash
sudo openssl x509 -req -in /etc/kubernetes/pki/apiserver-etcd-client.csr -CA /etc/kubernetes/pki/etcd/ca.crt -CAkey /etc/kubernetes/pki/etcd/ca.key -CAcreateserial -out /etc/kubernetes/pki/apiserver-etcd-client.crt -days 365
```

**Verificar los permisos:**

```bash
sudo chmod 600 /etc/kubernetes/pki/apiserver-etcd-client.key
sudo chmod 644 /etc/kubernetes/pki/apiserver-etcd-client.crt
```

## 7. Reiniciar servicios

**Recarga y reinicia ambos servicios:**

```bash
sudo systemctl daemon-reload
sudo systemctl restart etcd
sudo systemctl restart kube-apiserver
```


## 8. Verificar los logs

Verifica que no haya errores de certificados en los logs:

```bash
sudo journalctl -u etcd -f
sudo journalctl -u kube-apiserver -f
```