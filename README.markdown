
## 基于阿里云OSS的数据摆渡系统(网闸)

### 一、原理：
劫持用户上传请求到nginx，解析内容后重新签名，再进行审核，审核通过后使用oss sdk bucket拷贝到目的bucket即可：
https://help.aliyun.com/document_detail/88465.html?spm=a2c4g.11186623.6.803.41683bf5ngkaSU
![](media/15698060460859/15698101433423.jpg)
### 二、解决的问题：
OSS上传的文件审计需要定位到人。默认一个部门操作一个bucket使用一个key，若要定位到人，则需要给每个人新建唯一key，在人数较多，且bucket较多的情况下，配置很复杂，易出错。且存在key泄露的风险。
该系统颁发给每个用户一个伪造的Key，Secret。用户使用该K,S上传文件到摆渡系统，摆渡系统根据该K,S判断用户有效性，并替换Key，Secret为真实K,S。

### 三、通过策略配置三类OSS bucket
1、只能在VPC内使用，可以上传下载。
2、在VPC外上传下载。在VPC内可以下载。
3、在内可以上传，在外可以下载。（只有一个，供摆渡系统使用）。

依赖：
redis
用于保存，用于鉴权，判断定位上传的用户。

代码只包含nginx-filter部分。

### 四、使用
1、配置nginx:
1.1 环境变量中添加

```
# redis host
DATAGATE_REDIS_HOST=''
# redis port
DATAGATE_REDIS_PORT=
# redis password
DATAGATE_REDIS_PWD=''
# 用于摆渡的bucket（缓冲，暂存）
DATAGATE_BUCKET=''

```
1.2 nginx配置

```
worker_processes  4;
events {
    worker_connections 1024;
}

env DATAGATE_REDIS_HOST;
env DATAGATE_REDIS_PORT;
env DATAGATE_REDIS_PWD;
env DATAGATE_BUCKET;

http {
    server {
        listen 80;
        server_name *.oss-cn-beijing-internal.aliyuncs.com;
        access_log logs/filter-test.access.log;
        error_log logs/filter-test.error.log info;

        location ~ / {
            lua_code_cache off;
            default_type text/html;
            access_by_lua_file "/usr/local/openresty/nginx/conf/filter/filter.lua";
            # log module 
            log_by_lua_file "/usr/local/openresty/nginx/conf/filter/filter_log.lua";
            # server
            proxy_pass http://xxxx.oss-cn-beijing-internal.aliyuncs.com/;
        }
    }
    client_max_body_size 200m;
    # dns server (redis)
    resolver x.x.x.x;
}
```
2、redis中提前写入伪造的用户信息：
格式如下：

```
'DataGate:TokenToUser:{token}':'erxiao.wang'
'DataGate:TokenToBucket:token':'upload_bucket'
'DataGate:KeyToSecret:{key}':'key对应的真实Secret'

如：token = testToken , 用于上传的bucket name为upload_bucket,用于上传的key，secret为testKey,testSecret
'DataGate:TokenToUser:testToken':'erxiao.wang'
'DataGate:TokenToBucket:testToken':'upload_bucket'
'DataGate:KeyToSecret:testKey':'testSecret'
```

3、修改配置：
以python sdk v2.6.1为例（java v2.8.3类似）:

替换Key为 testKey@testToken，Secret为任意值即可（如123456，sdk会校验该参数不为空）。

原配置：

```
# 阿里云主账号AccessKey拥有所有API的访问权限，风险很高。强烈建议您创建并使用RAM账号进行API访问或日常运维，请登录 https://ram.console.aliyun.com 创建RAM账号。
# 假设key为 testKey
auth = oss2.Auth('testKey', '****')

# Endpoint以beijing为例，其它Region请按实际情况填写。
bucket = oss2.Bucket(auth, 'http://oss-cn-beijing-internal.aliyuncs.com', 'upload_bucket')

# 
bucket.put_object_from_file('<yourObjectName>', '<yourLocalFile>')
```
修改后的配置：

```
# 阿里云主账号AccessKey拥有所有API的访问权限，风险很高。强烈建议您创建并使用RAM账号进行API访问或日常运维，请登录 https://ram.console.aliyun.com 创建RAM账号。
auth = oss2.Auth('testKey@testToken', '123456')

# Endpoint以杭州为例，其它Region请按实际情况填写。
bucket = oss2.Bucket(auth, 'http://oss-cn-beijing-internal.aliyuncs.com', 'upload_bucket')

# 修改 yourObjectName = bucketName + objectName ,用于上传到不同的目录（强烈建议，修改该目录，否则可能存在文件被覆盖的情况，同时建议上传文件名或上传的文件路径包含时间戳，如 upload_bucket/sdk/2019_06_26/xxx.bin 或upload_bucket/sdk/xxx_2019_06_26.bin）
bucket.put_object_from_file('<bucketName>/<yourObjectName>', '<yourLocalFile>')
```