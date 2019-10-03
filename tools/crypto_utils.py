# Crypto related utils

import math
from Crypto.Cipher import AES
import hashlib, hmac

from common_utils import *

# Import our ECC python primitives
sys.path.append(os.path.abspath(os.path.dirname(sys.argv[0])) + "/" + "../externals/libecc/scripts/")
from expand_libecc import *

# Get the curve and signature algorithm from a structured key
# [RB] FIXME: the algorithm and curve 'enum' values are hardcoded
# and supposed fixed in libecc. This is a bit tedious and error prone:
# we should ideally extract this information from the libecc headers.
def get_curve_from_key(structured_key_buffer):
    algo  = ord(structured_key_buffer[1])
    curve = ord(structured_key_buffer[2])
    prime = None
    a = None
    b = None
    gx = None
    gy = None
    order = None
    cofactor = None
    if algo == 1:
        # We only support ECDSA
        ret_alg = "ECDSA"
    else:
        ret_alg = None
    if curve == 1:
        ret_curve = "FRP256V1"
        prime = 0xF1FD178C0B3AD58F10126DE8CE42435B3961ADBCABC8CA6DE8FCF353D86E9C03
        a = 0xF1FD178C0B3AD58F10126DE8CE42435B3961ADBCABC8CA6DE8FCF353D86E9C00
        b = 0xEE353FCA5428A9300D4ABA754A44C00FDFEC0C9AE4B1A1803075ED967B7BB73F
        gx = 0xB6B3D4C356C139EB31183D4749D423958C27D2DCAF98B70164C97A2DD98F5CFF
        gy = 0x6142E0F7C8B204911F9271F0F3ECEF8C2701C307E8E4C9E183115A1554062CFB
        order = 0xF1FD178C0B3AD58F10126DE8CE42435B53DC67E140D2BF941FFDD459C6D655E1
        cofactor = 1
    elif curve == 8:
        ret_curve = "BRAINPOOLP256R1"
        prime = 76884956397045344220809746629001649093037950200943055203735601445031516197751
        a = 0x7D5A0975FC2C3057EEF67530417AFFE7FB8055C126DC5C6CE94A4B44F330B5D9
        b = 0x26DC5C6CE94A4B44F330B5D9BBD77CBF958416295CF7E1CE6BCCDC18FF8C07B6
        gx = 0x8BD2AEB9CB7E57CB2C4B482FFC81B7AFB9DE27E1E3BD23C23A4453BD9ACE3262
        gy = 0x547EF835C3DAC4FD97F8461A14611DC9C27745132DED8E545C1D54C72F046997
        order = 0xA9FB57DBA1EEA9BC3E660A909D838D718C397AA3B561A6F7901E0E82974856A7
        cofactor = 1
    elif curve == 4:
        ret_curve = "SECP256R1"
        prime = 115792089210356248762697446949407573530086143415290314195533631308867097853951
        a = 115792089210356248762697446949407573530086143415290314195533631308867097853948
        b = 41058363725152142129326129780047268409114441015993725554835256314039467401291
        gx = 48439561293906451759052585252797914202762949526041747995844080717082404635286
        gy = 36134250956749795798585127919587881956611106672985015071877198253568414405109
        order = 115792089210356248762697446949407573529996955224135760342422259061068512044369
        cofactor = 1
    else:
        ret_curve = None
    return (ret_alg, ret_curve, prime, a, b, gx, gy, order, cofactor)
        
def get_sig_len(structured_key_buffer):
    # We only support 64 bytes (r, s) as the signature length for now ...
    # [RB] FIXME: use a more flexible way to compute this from the key
    return 64

# Python 2/3 abstraction layer for hash function
def local_sha256(arg_in):
    (a, b, c) = sha256(arg_in)
    return (a, b, c)

# Python 2/3 abstraction layer for HMAC
class local_hmac:
    hm = None
    def __init__(self, key, digestmod=hashlib.sha256):
        key = str_encode(key)
        self.hm = hmac.new(key, digestmod=digestmod)
        return
    def update(self, in_str):
        in_str = str_encode(in_str)
        if self.hm == None:
            return
        else:
            self.hm.update(in_str)
            return
    def digest(self):
        if self.hm == None:
            return None
        else:
            d = self.hm.digest()
            return str_decode(d)
    @staticmethod
    def new(key, digestmod=hashlib.sha256):
        return local_hmac(key, digestmod=digestmod)

# Python 2/3 abstraction layer for AES
class local_AES:
    aes = None
    iv = None
    def  __init__(self, key, mode, iv=None, counter=None):
        key = str_encode(key)
        if iv != None:
            self.iv = iv
            iv = str_encode(iv)
            if mode == AES.MODE_CTR:
                if counter == None:
                    self.aes = AES.new(key, mode, counter=self.counter_inc)
                else:
                    self.aes = AES.new(key, mode, counter=counter)
            else:
                self.aes = AES.new(key, mode, iv)
            return
        else:
            if mode == AES.MODE_CTR:
                if counter == None:
                    self.iv = expand(inttostring(0), 128, "LEFT")
                    self.aes = AES.new(key, mode, counter=self.counter_inc)
                else:
                    self.aes = AES.new(key, mode, counter=counter)
            else:
                self.aes = AES.new(key, mode)
            return
    def counter_inc(self):
        curr_iv = expand(inttostring((stringtoint(self.iv))), 128, "LEFT")
        self.iv = expand(inttostring((stringtoint(self.iv)+1)), 128, "LEFT")
        curr_iv = str_encode(curr_iv)
        return curr_iv
    def encrypt(self, data):
        data = str_encode(data)
        ret = str_decode(self.aes.encrypt(data))
        return ret
    def decrypt(self, data):
        data = str_encode(data)
        ret = str_decode(self.aes.decrypt(data))
        return ret
    @staticmethod
    def new(key, mode, iv=None, counter=None):
        return local_AES(key, mode, iv=iv, counter=counter)

# Python 2/3 abstraction layer for PBKDF2
def local_pbkdf2_hmac(hash_func, pin, salt, pbkdf2_iterations):
    if is_python_2() == False:
        pin = str_encode(pin)
        salt = str_encode(salt)
    dk = hashlib.pbkdf2_hmac(hash_func, pin, salt, pbkdf2_iterations)
    return str_decode(dk)

# Encrypt the local pet key using PBKDF2
def enc_local_pet_key(pet_pin, salt, pbkdf2_iterations, master_symmetric_local_pet_key):
    ## Master symmetric 'pet key' to be used for local credential encryption on the platform
    # Use PBKDF2-SHA-512 to derive our local encryption keys
    dk = local_pbkdf2_hmac('sha512', pet_pin, salt, pbkdf2_iterations)
    # The encrypted key is the encryption with AES-ECB 128 of the generated keys.
    # We have 64 bytes to encrypt and the PBKDF2 results in 64 bytes, hence
    # we can encrypt each chunk with AES-ECB and an associated key
    cipher1 = local_AES.new(dk[:16],   AES.MODE_ECB)
    cipher2 = local_AES.new(dk[16:32], AES.MODE_ECB)
    cipher3 = local_AES.new(dk[32:48], AES.MODE_ECB)
    cipher4 = local_AES.new(dk[48:],   AES.MODE_ECB)
    enc_master_symmetric_local_pet_key = cipher1.encrypt(master_symmetric_local_pet_key[:16]) + cipher2.encrypt(master_symmetric_local_pet_key[16:32]) + cipher3.encrypt(master_symmetric_local_pet_key[32:48]) + cipher4.encrypt(master_symmetric_local_pet_key[48:])
    return enc_master_symmetric_local_pet_key

# Decrypt the local pet key using PBKDF2
def dec_local_pet_key(pet_pin, salt, pbkdf2_iterations, enc_master_symmetric_local_pet_key):
    ## Master symmetric 'pet key' to be used for local credential encryption on the platform
    # Use PBKDF2-SHA-512 to derive our local encryption keys
    dk = local_pbkdf2_hmac('sha512', pet_pin, salt, pbkdf2_iterations)
    master_symmetric_local_pet_key = None
    # We locally dercypt the key
    # The decrypted key is the decryption with AES-ECB 128 of the generated keys.
    # We have 64 bytes to encrypt and the PBKDF2 results in 64 bytes, hence
    # we can encrypt each chunk with AES-ECB and an associated key
    cipher1 = local_AES.new(dk[:16],   AES.MODE_ECB)
    cipher2 = local_AES.new(dk[16:32], AES.MODE_ECB)
    cipher3 = local_AES.new(dk[32:48], AES.MODE_ECB)
    cipher4 = local_AES.new(dk[48:],   AES.MODE_ECB)
    master_symmetric_local_pet_key = cipher1.decrypt(enc_master_symmetric_local_pet_key[:16]) + cipher2.decrypt(enc_master_symmetric_local_pet_key[16:32]) + cipher3.decrypt(enc_master_symmetric_local_pet_key[32:48]) + cipher4.decrypt(enc_master_symmetric_local_pet_key[48:])
    return master_symmetric_local_pet_key

# Decrypt our local private data
# [RB] FIXME: private and public keys lengths are hardcoded here ... we should be more flexible!
# Same for PBKDF2 iterations.
# These lengths should be infered from other files
def decrypt_platform_data(encrypted_platform_bin_file, pin, data_type, override_local_pet_key_handler=None, card=None):
    data = read_in_file(encrypted_platform_bin_file)
    index = 0
    decrypt_platform_data.iv = data[index:index+16]
    index += 16
    salt = data[index:index+16]
    index += 16
    hmac_tag = data[index:index+32]
    index += 32
    token_pub_key_data = data[index:index+99]
    index += 99
    platform_priv_key_data = data[index:index+35]
    index += 35
    platform_pub_key_data = data[index:index+99]
    index += 99
    firmware_sig_pub_key_data = None
    if (data_type == "dfu") or (data_type == "sig"):
        firmware_sig_pub_key_data = data[index:index+99]
        index += 99
    # Do we have other keys to decrypt? (if we do not use a sig token)
    firmware_sig_priv_key_data = None
    firmware_sig_sym_key_data = None
    encrypted_local_pet_key_data = None
    if (len(data) > index):
        firmware_sig_priv_key_data = data[index:index+35]
        index += 35
        firmware_sig_sym_key_data = data[index:index+32]
        index += 32
        encrypted_local_pet_key_data = data[index:index+64]
        index += 64
    # Derive the decryption key
    pbkdf2_iterations = 4096
    if card == None:
        dk = dec_local_pet_key(pin, salt, pbkdf2_iterations, encrypted_local_pet_key_data)
    else:
        dk = override_local_pet_key_handler(pin, salt, pbkdf2_iterations, encrypted_local_pet_key_data, card, data_type)
    # Now compute and check the HMAC, and decrypt local data
    hmac_key = dk[32:]
    # Check the mac tag
    hm = local_hmac.new(hmac_key, digestmod=hashlib.sha256)
    hm.update(decrypt_platform_data.iv + salt + token_pub_key_data + platform_priv_key_data + platform_pub_key_data)
    if firmware_sig_pub_key_data != None:
        hm.update(firmware_sig_pub_key_data)
    if firmware_sig_priv_key_data != None:
        hm.update(firmware_sig_priv_key_data)
    if firmware_sig_sym_key_data != None:
        hm.update(firmware_sig_sym_key_data)
    hmac_tag_ref = hm.digest()
    if hmac_tag != hmac_tag_ref:
        print("Error when decrypting local data with the PET pin: hmac not OK!")
        sys.exit(-1)
    # Decrypt
    enc_key = dk[:16]
    cipher = local_AES.new(enc_key, AES.MODE_CTR, iv=decrypt_platform_data.iv)
    dec_token_pub_key_data = cipher.decrypt(token_pub_key_data)
    dec_platform_priv_key_data = cipher.decrypt(platform_priv_key_data)
    dec_platform_pub_key_data = cipher.decrypt(platform_pub_key_data)
    dec_firmware_sig_pub_key_data = None
    if firmware_sig_pub_key_data != None:
        dec_firmware_sig_pub_key_data = cipher.decrypt(firmware_sig_pub_key_data)
    dec_firmware_sig_priv_key_data = None
    if firmware_sig_priv_key_data != None:
        dec_firmware_sig_priv_key_data = cipher.decrypt(firmware_sig_priv_key_data)
    dec_firmware_sig_sym_key_data = None
    if firmware_sig_sym_key_data != None:
        dec_firmware_sig_sym_key_data = cipher.decrypt(firmware_sig_sym_key_data)

    return dec_token_pub_key_data, dec_platform_priv_key_data, dec_platform_pub_key_data, dec_firmware_sig_pub_key_data, dec_firmware_sig_priv_key_data, dec_firmware_sig_sym_key_data, salt, pbkdf2_iterations
