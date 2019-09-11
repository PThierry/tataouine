#! /usr/bin/env python
# -*- coding: utf-8 -*-

# Encrypt a firmware and sign it using interactions with
# the SIG token

# Import our local utils
from common_utils import *
from crypto_utils import *
from firmware_utils import *

def PrintUsage():
    executable = os.path.basename(__file__)
    print("Error when executing %s\n\tUsage:\t%s keys_path firmware_to_sign firmware_magic firmware_partition_type firmware_version firmware_chunk_size usb_vid usb_pid" % (executable, executable))
    sys.exit(-1)

if __name__ == '__main__':
    # Register Ctrl+C handler
    signal.signal(signal.SIGINT, handler)
    # Get the arguments
    if len(sys.argv) <= 6:
        PrintUsage()
    keys_path = sys.argv[1]
    firmware_to_sign_file = sys.argv[2]
    firmware_magic = int(sys.argv[3], 0)
    firmware_partition_type = sys.argv[4]

    # Check if the firmware is provided as an integer or as a string version
    firmware_string_version = None
    try:
        firmware_int_version = int(sys.argv[5], 0)
        if firmware_int_version > 0xffffffff:
            print("Error: invalid version field: %d (too big)" % firmware_int_version);
            sys.exit(-1);      
        firmware_string_version = [ (firmware_int_version & 0xff000000) >> 24, (firmware_int_version & 0xff0000) >> 16, (firmware_int_version & 0xff00) >> 8, firmware_int_version & 0xff ]
    except:
        firmware_string_version = [ int(x) for x in sys.argv[5].replace('-','.').split(".") ]
    if len(firmware_string_version) > 4:
        print("Error: provided version %s exceeds maximumum version value (on 32 bits)" % sys.argv[5])
    if len(firmware_string_version) < 4:
        # Perform padding on the left
        firmware_string_version = ([0]*(4-len(firmware_string_version))) + firmware_string_version
    firmware_version = 0;
    pos = 24;
    if len(firmware_string_version) > 4:
        print("Error: version string too long");
        sys.exit(-1);
    for value in firmware_string_version:
        if int(value)>255:
            print("Error: invalid version field: %d" % value);
            sys.exit(-1);
        firmware_version = firmware_version + (int(value) << pos);
        pos -= 8;

    firmware_chunk_size = int(sys.argv[6], 0)
    # Default values for the DFU suffix
    usb_vid = usb_pid = 0xffff
    if len(sys.argv) > 7:
        usb_vid = int(sys.argv[7], 16)
    if len(sys.argv) > 8:
        usb_pid = int(sys.argv[8], 16)

    if usb_vid > 0xffff:
        print("Error: provided USB Vendor ID %d is invalid (> 0xffff)" % (usb_vid))
        sys.exit(-1)
    if usb_pid > 0xffff:
        print("Error: provided USB Product ID %d is invalid (> 0xffff)" % (usb_pid))
        sys.exit(-1)

    if not os.path.isfile(firmware_to_sign_file):
        print("Error: provided firmware file %s does not exist!" % (firmware_to_sign_file))
        sys.exit(-1)
    firmware_partition_type = partitions_types[firmware_partition_type]
    if (firmware_chunk_size < 0) or (firmware_version < 0) or (firmware_chunk_size < 0):
        print("Error: negative values are not allowed as arguments ...")
        sys.exit(-1)
    # Sanity checks
    if firmware_magic > (0x1 << 32):
        print("Error: provided firmware_magic %d exceeds maximum size of 4 bytes ..." % (firmware_magic))
        sys.exit(-1)
    if firmware_version > (0x1 << 32):
        print("Error: provided firmware_version %d exceeds maximum size of 4 bytes ..." % (firmware_version))
        sys.exit(-1)
    # Check that we have a reasonable chunk size to be sure to call the token
    # a reasonable number of times
    if firmware_chunk_size > 65536:
        print("Error: provided firmware_chunk_size %d exceeds maximum allowed size of 65536 ..." % (firmware_chunk_size))
        sys.exit(-1)
    # Convert magic, version and chunk_size to strings in big endian
    firmware_magic = expand(inttostring(firmware_magic), 32, "LEFT")
    firmware_version = expand(inttostring(firmware_version), 32, "LEFT")
    firmware_chunk_size_str = expand(inttostring(firmware_chunk_size), 32, "LEFT")
    # Read the firmware file in a buffer
    firmware_to_sign = read_in_file(firmware_to_sign_file)

    # Current script path
    SCRIPT_PATH = os.path.abspath(os.path.dirname(sys.argv[0])) + "/"
    # Variable used when the SIG token is used
    card = None
    scp_sig = None
    # Variables used when the SIG token is NOT used and all the key
    # are locally encrypted
    dec_token_pub_key_data = None
    dec_platform_priv_key_data = None
    dec_platform_pub_key_data = None
    dec_firmware_sig_pub_key_data = None
    dec_firmware_sig_priv_key_data = None
    dec_firmware_sig_sym_key_data = None

    # Check if we want to use an external token for the signature or not
    USE_SIG_TOKEN = is_sig_token_used(keys_path+"/SIG/encrypted_platform_sig_keys.bin")

    if USE_SIG_TOKEN == True:
        from token_utils import *
        card = connect_to_token("SIG")
        scp_sig = token_full_unlock(card, "sig", keys_path+"/SIG/encrypted_platform_sig_keys.bin") # pet_pin="1234", user_pin="1234", force_pet_name_accept = True)
    else:
        local_storage_password = get_user_input("Please provide the local storage password for SIG (firmware signature):\n")
        # Decrypt the local keys
        dec_token_pub_key_data, dec_platform_priv_key_data, dec_platform_pub_key_data, dec_firmware_sig_pub_key_data, dec_firmware_sig_priv_key_data, dec_firmware_sig_sym_key_data, _, _ = decrypt_platform_data(keys_path+"/SIG/encrypted_platform_sig_keys.bin", local_storage_password, "sig")

    # ======================
    # Structure of a signed image is:
    # Header + MAX_CHUNK_SIZE(4 bytes) + IV + HMAC(previous) + SIG + ENC(firmware)
    # The signature covers Header + MAX_CHUNK_SIZE + firmware

    # ======================
    # We forge the basic header = magic on 4 bytes || partition type on 4 bytes || version on 4 bytes || len of data after the header on 4 bytes || siglen on 4 bytes
    sigtype = None
    if USE_SIG_TOKEN == True:
        sigtype, sw1, sw2 = scp_sig.token_sig_get_sig_type()
        if (sw1 != 0x90) or (sw2 != 0x00):
            print("Error:  SIG token APDU error ...")
            sys.exit(-1)
    else:
        sigtype = expand(inttostring(get_sig_len(dec_firmware_sig_priv_key_data)), 32, "LEFT") + dec_firmware_sig_priv_key_data[:2]
    siglen = sigtype[:4]
    libeccparams = sigtype[-2:]
    # Sanity check on the ECDSA signature algorithm
    the_sig = stringtoint(libeccparams[0])
    if ((len(sigtype) != 6) or (the_sig != 0x01)):
        print("Error: signature type %d sent by the card is not conforming to ECDSA ..." % (the_sig))
        sys.exit(-1)

    data_len_encapsulated = expand(inttostring(len(firmware_to_sign)), 32, "LEFT")
    header = firmware_magic + expand(inttostring(firmware_partition_type), 32, "LEFT") + firmware_version + data_len_encapsulated + siglen

    # ======================
    # The signature on the header + chunk_size + the CLEAR text firmware
    # NOTE1: since we want to check the firmware once it is written on flash, we
    # have to sign its clear text form (and not the encrypted one).
    # NOTE2: because of ECDSA limitations of the current javacard API, we cannot
    # compute ECDSA on raw data since the card performs the hash function. Hence, we are
    # deemed to compute ECDSA with double SHA-256:
    # firmware_sig = ECDSA_SIG(SHA-256(header || firmware))
    (to_sign, _, _) = local_sha256(header + firmware_chunk_size_str + firmware_to_sign)
    sig = None
    if USE_SIG_TOKEN == True:
        sig, sw1, sw2  = scp_sig.token_sig_sign_firmware(to_sign)
        if (sw1 != 0x90) or (sw2 != 0x00):
            print("Error:  SIG token APDU error ...")
            sys.exit(-1)
        signed_data = to_sign + sig
        resp, sw1, sw2 = scp_sig.token_sig_verify_firmware(signed_data)
        if (sw1 != 0x90) or (sw2 != 0x00):
            print("Error:  SIG token APDU error ...")
            sys.exit(-1)
    else:
        # Software ECDSA signature
        ret_alg, ret_curve, prime, a, b, gx, gy, order, cofactor = get_curve_from_key(dec_firmware_sig_pub_key_data)
        c = Curve(a, b, prime, order, cofactor, gx, gy, cofactor * order, ret_alg, None)
        ecdsa_privkey = PrivKey(c, stringtoint(dec_firmware_sig_priv_key_data[3:3+32]))
        ecdsa_keypair = KeyPair(None, ecdsa_privkey)
        (sig, _) = ecdsa_sign(sha256, ecdsa_keypair, to_sign)


    sig_session_iv = None
    # We first begin a signing session to get the iv and the header HMAC
    if USE_SIG_TOKEN == True:
        sig_session_iv, sw1, sw2 = scp_sig.token_sig_begin_sign_session(header + firmware_chunk_size_str + sig)
        if (sw1 != 0x90) or (sw2 != 0x00):
            print("Error:  SIG token APDU error ...")
            sys.exit(-1)
    else:
        # Generate random
        sig_session_iv = gen_rand_string(16)
        # Compute the HMAC, and concatenate them, HMAC key is first 32 bytes of master key
        hm = local_hmac.new(dec_firmware_sig_sym_key_data[:32], digestmod=hashlib.sha256)
        hm.update(header + firmware_chunk_size_str + sig_session_iv + sig)
        sig_session_iv += hm.digest()

    # ======================
    # The encryption of the firmware chunks of
    # Each chunk is encrypted using AES-CTR and the current session key and an IV of zero

    # Split the firmware in chunks
    n_chunks = int(len(firmware_to_sign) // firmware_chunk_size)
    if len(firmware_to_sign) % firmware_chunk_size != 0:
        n_chunks += 1

    encrypted_firmware = ""

    if USE_SIG_TOKEN == True:
        # The SIG token will derive keys for us
        local_key_to_derive = None
    else:
        # We use software crypto to derive keys
        local_key_to_derive = sig_session_iv[:16]
    for i in range(0, n_chunks):
        print("\tXXXXXXXXXXXXXXXXX ENCRYPTING CHUNK %04x XXXXXXXXXXXXXXXXX" % (i))
        chunk_key = None
        if USE_SIG_TOKEN == True:
            chunk_key, sw1, sw2 = scp_sig.token_sig_derive_key(i)
            if (sw1 != 0x90) or (sw2 != 0x00):
                print("Error:  SIG token APDU error ...")
                sys.exit(-1)
        else:
            aes_cbc_ctx = local_AES.new(dec_firmware_sig_sym_key_data[32:32+16], AES.MODE_CBC, iv=dec_firmware_sig_sym_key_data[32+16:])
            chunk_key = aes_cbc_ctx.encrypt(local_key_to_derive)

            # Increment the session iv
            local_key_to_derive = expand(inttostring((stringtoint(local_key_to_derive)+1)), 128, "LEFT")
        # Initialize AES-CTR IV to 0
        chunk_iv = inttostring(0)
        if i != n_chunks-1:
            chunk = firmware_to_sign[(i*firmware_chunk_size) : ((i+1)*firmware_chunk_size)]
        else:
            chunk = firmware_to_sign[(i*firmware_chunk_size):]
        aes = local_AES.new(chunk_key, AES.MODE_CTR, iv=chunk_iv)
        encrypted_firmware += aes.encrypt(chunk)
        print("\tXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")

    # The header is zero padded to a crypto chunk size in order to properly deal with alignment issues
    full_header = header + firmware_chunk_size_str + sig_session_iv + sig
    full_header_padding_len = firmware_chunk_size - (len(full_header) % firmware_chunk_size)
    padded_full_header = full_header + ('\x00' * full_header_padding_len)
    # Compute the DFU suffix on 16 bytes
    dfu_suffix = inttostring(0xffff) + expand(inttostring(usb_pid), 16, "LEFT")[::-1] + expand(inttostring(usb_vid), 16, "LEFT")[::-1] + "\x00\x01\x55\x46\x44\x10"
    to_save = padded_full_header + encrypted_firmware + dfu_suffix
    dfu_suffix_crc32 = expand(inttostring(dfu_crc32_update(to_save, 0xffffffff)), 32, "LEFT")[::-1]
    # Save the header and signed/encrypted firmware in a file
    save_in_file(to_save + dfu_suffix_crc32, firmware_to_sign_file+".signed")
