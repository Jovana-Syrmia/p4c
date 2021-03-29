#include <core.p4>
#include <psa.p4>

struct EMPTY { };

header hdr_t {
    bit<8> field;
}

control Wrapped(inout bit<8> valueSet) {
    action set(bit<8> value) {
        valueSet = value;
    }
    table doSet {
        actions = {
            set();
        }
        default_action = set(8w0);
    }
   apply {
        doSet.apply();
   }
}

control Wrapper(inout bit<8> value) { 
   Wrapped() wrapped; 
   apply { wrapped.apply(value); } 
}

parser MyIP(
    packet_in buffer,
    out hdr_t a,
    inout EMPTY b,
    in psa_ingress_parser_input_metadata_t c,
    in EMPTY d,
    in EMPTY e) {

    state start {
        buffer.extract(a);
        transition accept;
    }
}

parser MyEP(
    packet_in buffer,
    out EMPTY a,
    inout EMPTY b,
    in psa_egress_parser_input_metadata_t c,
    in EMPTY d,
    in EMPTY e,
    in EMPTY f) {
    state start {
        transition accept;
    }
}

control MyIC(
    inout hdr_t a,
    inout EMPTY b,
    in psa_ingress_input_metadata_t c,
    inout psa_ingress_output_metadata_t d) {

    Wrapper() wrapper;
    apply { 
        wrapper.apply(a.field);
    }
}

control MyEC(
    inout EMPTY a,
    inout EMPTY b,
    in psa_egress_input_metadata_t c,
    inout psa_egress_output_metadata_t d) {
    apply { }
}

control MyID(
    packet_out buffer,
    out EMPTY a,
    out EMPTY b,
    out EMPTY c,
    inout hdr_t d,
    in EMPTY e,
    in psa_ingress_output_metadata_t f) {
    apply { }
}

control MyED(
    packet_out buffer,
    out EMPTY a,
    out EMPTY b,
    inout EMPTY c,
    in EMPTY d,
    in psa_egress_output_metadata_t e,
    in psa_egress_deparser_input_metadata_t f) {
    apply { }
}

IngressPipeline(MyIP(), MyIC(), MyID()) ip;
EgressPipeline(MyEP(), MyEC(), MyED()) ep;

PSA_Switch(
    ip,
    PacketReplicationEngine(),
    ep,
    BufferingQueueingEngine()) main;