#include <core.p4>
#include <bmv2/psa.p4>

typedef bit<32> ipv4_addr_t;
typedef bit<32> teid_t;
struct empty_metadata_t {
}

header ethernet_t {
    bit<48> dst_addr;
    bit<48> src_addr;
    bit<16> ether_type;
}

header ipv4_t {
    bit<8>      ver_ihl;
    bit<8>      diffserv;
    bit<16>     total_len;
    bit<16>     identification;
    bit<16>     flags_offset;
    bit<8>      ttl;
    bit<8>      protocol;
    bit<16>     hdr_checksum;
    ipv4_addr_t src_addr;
    ipv4_addr_t dst_addr;
}

header udp_t {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> length;
    bit<16> checksum;
}

header gtpu_t {
    bit<8>  flags;
    bit<8>  msgtype;
    bit<16> msglen;
    teid_t  teid;
}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t     ipv4;
    udp_t      udp;
    gtpu_t     gtpu;
}

struct local_metadata_t {
    bit<48> dst_mac;
    bit<48> src_mac;
    bit<32> src_addr;
    bit<32> dst_addr;
    bit<16> l4_sport;
    bit<16> l4_dport;
}

parser packet_parser(packet_in packet, out headers_t headers, inout local_metadata_t local_metadata, in psa_ingress_parser_input_metadata_t istd, in empty_metadata_t resub_meta, in empty_metadata_t recirc_meta) {
    @name("packet_parser.gtpu") gtpu_t gtpu_0;
    bit<64> tmp;
    state start {
        packet.extract<ethernet_t>(headers.ethernet);
        transition select(headers.ethernet.ether_type) {
            16w0x800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract<ipv4_t>(headers.ipv4);
        transition select(headers.ipv4.protocol) {
            8w17: parse_udp;
            default: accept;
        }
    }
    state parse_udp {
        packet.extract<udp_t>(headers.udp);
        tmp = packet.lookahead<bit<64>>();
        gtpu_0.setValid();
        gtpu_0.flags = tmp[63:56];
        gtpu_0.msgtype = tmp[55:48];
        gtpu_0.msglen = tmp[47:32];
        gtpu_0.teid = tmp[31:0];
        transition select(headers.udp.dst_port, tmp[63:56] & 8w0xfc) {
            (16w2152, 8w0x4): parse_gtpu;
            default: accept;
        }
    }
    state parse_gtpu {
        packet.extract<gtpu_t>(headers.gtpu);
        transition accept;
    }
}

control packet_deparser(packet_out packet, out empty_metadata_t clone_i2e_meta, out empty_metadata_t resubmit_meta, out empty_metadata_t normal_meta, inout headers_t headers, in local_metadata_t local_metadata, in psa_ingress_output_metadata_t istd) {
    @hidden action psaexamplelookahead133() {
        packet.emit<ethernet_t>(headers.ethernet);
        packet.emit<ipv4_t>(headers.ipv4);
        packet.emit<udp_t>(headers.udp);
    }
    @hidden table tbl_psaexamplelookahead133 {
        actions = {
            psaexamplelookahead133();
        }
        const default_action = psaexamplelookahead133();
    }
    apply {
        tbl_psaexamplelookahead133.apply();
    }
}

control ingress(inout headers_t headers, inout local_metadata_t local_metadata1, in psa_ingress_input_metadata_t istd, inout psa_ingress_output_metadata_t ostd) {
    @name("ingress.drop") action drop_1() {
        ostd.drop = true;
    }
    @name("ingress.ipv4_forward") action ipv4_forward(@name("port") PortId_t port) {
        ostd.egress_port = port;
        headers.ipv4.ttl = headers.ipv4.ttl + 8w255;
    }
    @name("ingress.ipv4_exact") table ipv4_exact_0 {
        key = {
            headers.ipv4.dst_addr: exact @name("headers.ipv4.dst_addr") ;
            headers.ipv4.src_addr: exact @name("headers.ipv4.src_addr") ;
        }
        actions = {
            ipv4_forward();
            drop_1();
        }
        size = 1024;
        default_action = drop_1();
    }
    apply {
        if (headers.ipv4.isValid()) {
            ipv4_exact_0.apply();
        }
    }
}

control egress(inout headers_t headers, inout local_metadata_t local_metadata, in psa_egress_input_metadata_t istd, inout psa_egress_output_metadata_t ostd) {
    apply {
    }
}

parser egress_parser(packet_in buffer, out headers_t headers, inout local_metadata_t local_metadata, in psa_egress_parser_input_metadata_t istd, in empty_metadata_t normal_meta, in empty_metadata_t clone_i2e_meta, in empty_metadata_t clone_e2e_meta) {
    state start {
        transition accept;
    }
}

control egress_deparser(packet_out packet, out empty_metadata_t clone_e2e_meta, out empty_metadata_t recirculate_meta, inout headers_t headers, in local_metadata_t local_metadata, in psa_egress_output_metadata_t istd, in psa_egress_deparser_input_metadata_t edstd) {
    apply {
    }
}

IngressPipeline<headers_t, local_metadata_t, empty_metadata_t, empty_metadata_t, empty_metadata_t, empty_metadata_t>(packet_parser(), ingress(), packet_deparser()) ingress_pipe;

EgressPipeline<headers_t, local_metadata_t, empty_metadata_t, empty_metadata_t, empty_metadata_t, empty_metadata_t>(egress_parser(), egress(), egress_deparser()) egress_pipe;

PSA_Switch<headers_t, local_metadata_t, headers_t, local_metadata_t, empty_metadata_t, empty_metadata_t, empty_metadata_t, empty_metadata_t, empty_metadata_t>(ingress_pipe, PacketReplicationEngine(), egress_pipe, BufferingQueueingEngine()) main;

