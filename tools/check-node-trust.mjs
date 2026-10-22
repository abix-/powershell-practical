// Only built-in modules; inherited preload/trust overrides are cleared by the caller.
import https from 'node:https';

const negativeHosts = ['dv-g3b', 'dv-g3c', 'ov-g3b', 'ov-g3c', 'ev-g3b', 'ev-g3c']
    .flatMap(issuer => ['', '-aaa'].map(cross => `${issuer}${cross}-emudhra.we-have-a-problem.com`));
negativeHosts.push('dv-g3b-noct-emudhra.we-have-a-problem.com', 'dv-g3b-aaa-noct-emudhra.we-have-a-problem.com');
const certificateErrors = new Set(['CERT_REVOKED', 'CERT_HAS_EXPIRED', 'CERT_NOT_YET_VALID',
    'DEPTH_ZERO_SELF_SIGNED_CERT', 'SELF_SIGNED_CERT_IN_CHAIN', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE',
    'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'ERR_TLS_CERT_ALTNAME_INVALID']);

function check(host) {
    return new Promise(resolve => {
        const request = https.request(`https://${host}/`, {
            method: 'HEAD', agent: false, rejectUnauthorized: true,
            signal: AbortSignal.timeout(8000),
        }, response => {
            const status = response.statusCode;
            response.destroy();
            resolve({ host, classification: 'tls_accepted', http_status: status });
        });
        request.on('error', error => resolve({
            host, classification: certificateErrors.has(error.code) ? 'certificate_rejected' : 'unverified_transport_failure',
            code: error.code ?? 'unknown',
        }));
        request.end();
    });
}

const checks = [];
for (const host of ['rustsec.org', ...negativeHosts]) checks.push(await check(host));
console.log(JSON.stringify({
    node_version: process.versions.node, openssl_version: process.versions.openssl,
    scope: 'Isolated installed Node bundled-CA defaults with verification enabled; not proof of existing application options or environment.',
    positive_control_passed: checks[0].classification === 'tls_accepted', checks,
}));
