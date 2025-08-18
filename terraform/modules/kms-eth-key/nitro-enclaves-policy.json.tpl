{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow administration of the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": ${jsonencode(admin_arns)}
      },
      "Action": [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow use of the key for Ethereum signing",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${irsa_role_arn}"
      },
      "Action": [
        "kms:Sign",
        "kms:GetPublicKey",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "kms.${region}.amazonaws.com",
          "kms:SigningAlgorithm": "ECDSA_SHA_256"
        }
      }
    },
    {
      "Sid": "Allow Nitro Enclave access with attestation",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${irsa_role_arn}"
      },
      "Action": [
        "kms:Sign",
        "kms:GetPublicKey",
        "kms:DescribeKey",
        "kms:Decrypt"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "kms.${region}.amazonaws.com",
          "kms:SigningAlgorithm": "ECDSA_SHA_256"
        },
        "StringEqualsIgnoreCase": {
          "kms:RecipientAttestation:ImageSha384": "${pcr0_hash}"
        }
      }
    },
    {
      "Sid": "Deny non-attested access to sensitive operations",
      "Effect": "Deny",
      "Principal": {
        "AWS": "${irsa_role_arn}"
      },
      "Action": [
        "kms:Sign",
        "kms:Decrypt"
      ],
      "Resource": "*",
      "Condition": {
        "Null": {
          "kms:RecipientAttestation:ImageSha384": "true"
        }
      }
    }
  ]
} 