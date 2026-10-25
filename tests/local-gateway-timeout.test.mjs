import {test} from 'node:test';
import assert from 'node:assert/strict';
import {configureGatewayTimeout} from '../scripts/local-gateway-timeout.mjs';

const fixture=`_format_version: "2.1"
services:
  - name: auth-v1
    read_timeout: 150000
  - name: functions-v1
    url: http://local-edge:8081/
    # Set request idle timeout to 150s to match hosted project
    read_timeout: 150000
    routes:
      - name: functions-v1-all
        paths: [/functions/v1/]
  - name: rest-v1
    read_timeout: 150000
consumers:
  - username: preserved
`;
test('only functions gateway timeout changes; update is idempotent',()=>{
 const result=configureGatewayTimeout(fixture);
 assert.match(result,/name: auth-v1\n    read_timeout: 150000/);
 assert.match(result,/name: rest-v1\n    read_timeout: 150000/);
 assert.match(result,/read_timeout: 195000/);
 assert.match(result,/username: preserved/);
 assert.match(result,/name: functions-v1-all/);
 assert.equal(configureGatewayTimeout(result),result);
});
test('unexpected config fails closed instead of rewriting other services',()=>{
 assert.throws(()=>configureGatewayTimeout(fixture.replace('name: functions-v1\n','name: other\n')));
 assert.throws(()=>configureGatewayTimeout(fixture.replace('    read_timeout: 150000\n    routes:','    routes:')));
 assert.throws(()=>configureGatewayTimeout(fixture+'  - name: functions-v1\n    read_timeout: 150000\n'));
});
