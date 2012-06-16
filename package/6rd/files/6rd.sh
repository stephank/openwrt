#!/bin/sh
# 6rd.sh - IPv6-in-IPv4 tunnel backend
# Copyright (c) 2010-2012 OpenWrt.org

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

find_6rd_wanif() {
	local if=$(ip -4 r l e 0.0.0.0/0); if="${if#default* dev }"; if="${if%% *}"
	[ -n "$if" ] && grep -qs "^ *$if:" /proc/net/dev && echo "$if"
}

find_6rd_wanip() {
	local ip=$(ip -4 a s dev "$1"); ip="${ip#*inet }"
	echo "${ip%%[^0-9.]*}"
}

tun_error() {
	local cfg="$1"; shift;

	[ -n "$1" ] && proto_notify_error "$cfg" "$@"
	proto_block_restart "$cfg"
}

proto_6rd_setup() {
	local cfg="$1"
	local iface="$2"
	local link="6rd-$cfg"

	json_get_var mtu mtu
	json_get_var ttl ttl
	json_get_var local4 ipaddr
	json_get_var remote4 peeraddr
	json_get_var ip6prefix ip6prefix
	json_get_var ip6prefixlen ip6prefixlen
	json_get_var ip4prefixlen ip4prefixlen

	[ -z "$ip6prefix" -o -z "$remote4" ] && {
		tun_error "$cfg" "MISSING_ADDRESS"
		return
	}

	# Figure out our IPv4 address.
	[ -z "$local4" ] && {
		local wanif=$(find_6rd_wanif)
		[ -z "$wanif" ] && {
			tun_error "$cfg" "NO_WAN_LINK"
			return
		}

		. /lib/network/config.sh
		local wancfg="$(find_config "$wanif")"
		[ -z "$wancfg" ] && {
			tun_error "$cfg" "NO_WAN_LINK"
			return
		}

		# If local4 is unset, guess local IPv4 address from the
		# interface used by the default route.
		[ -n "$wanif" ] && local4=$(find_6rd_wanip "$wanif")

		[ -z "$local4" ] && {
			tun_error "$cfg" "NO_WAN_LINK"
			return
		}
	}

	# Default to using the entire IPv4 address.
	local ip4prefixlen="${ip4prefixlen:-0}"
	# The unmasked part of the relay prefix must be zeroes.
	local ip4prefix=$(ipcalc.sh "$local4/$ip4prefixlen" | grep NETWORK)
	ip4prefix="${ip4prefix#NETWORK=}"

	# The IPv6 network allocated to us.
	local net6=$(6rdcalc "$ip6prefix::/$ip6prefixlen" "$local4/$ip4prefixlen")
	# Our own IPv6 in the network.
	local local6="${net6%%::*}::1"

	# Send the update.
	proto_init_update "$link" 1
	proto_add_ipv6_address "$local6" "$ip6prefixlen"
	proto_add_ipv6_route "::" 0 "::$remote4"

	proto_add_tunnel
	json_add_string mode sit
	json_add_int mtu "${mtu:-1280}"
	json_add_int ttl "${ttl:-64}"
	json_add_string local "$local4"
	json_add_string 6rd-prefix "$ip6prefix::/$ip6prefixlen"
	json_add_string 6rd-relay-prefix "$ip4prefix/$ip4prefixlen"
	proto_close_tunnel

	proto_send_update "$cfg"
}

proto_6rd_teardown() {
	local cfg="$1"
}

proto_6rd_init_config() {
	no_device=1
	available=1

	proto_config_add_int "mtu"
	proto_config_add_int "ttl"
	proto_config_add_string "peeraddr"
	proto_config_add_string "ip6prefix"
	proto_config_add_string "ip6prefixlen"
	proto_config_add_string "ip4prefixlen"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol 6rd
}
